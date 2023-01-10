import { aws_dynamodb, Duration, RemovalPolicy, Stack, StackProps } from 'aws-cdk-lib';
import * as path from 'path';
import * as fs from 'fs';
import * as dotenv from 'dotenv';
import { Construct } from 'constructs';
import * as cognito from 'aws-cdk-lib/aws-cognito';
import * as sm from 'aws-cdk-lib/aws-secretsmanager';
import * as appsync from 'aws-cdk-lib/aws-appsync';
import { AttributeType, Table } from 'aws-cdk-lib/aws-dynamodb';
import { Role, ServicePrincipal } from 'aws-cdk-lib/aws-iam';

dotenv.config();

export class InfrastructureStack extends Stack {
  constructor(scope: Construct, id: string, props?: StackProps) {
    super(scope, id, props);

    // AWS Cognito setup:
    const userPool = new cognito.UserPool(this, 'zeitplanUserPool', {
        userPoolName: 'zeitplan-userpool',
        selfSignUpEnabled: true,
        userVerification: {
            emailSubject: 'Verify your email for Zeitplan',
            emailBody: 'Thank you for signing up for Zeitplan! Your verification code is {####}',
            emailStyle: cognito.VerificationEmailStyle.CODE,
        },
        userInvitation: {
            emailSubject: 'You\'ve been invited to join Zeitplan!',
            emailBody: 'Hello {username}, you have been invited to join Zeitplan. Your temporary password is {####}',
        },
        signInAliases: {
            email: true,
        },
        autoVerify: {
            email: true,
        },
        mfa: cognito.Mfa.OPTIONAL,
        mfaSecondFactor: {
            sms: true,
            otp: true,
        },
        passwordPolicy: {
            minLength: 12,
            requireLowercase: true,
            requireUppercase: true,
            requireDigits: true,
            requireSymbols: true,
            tempPasswordValidity: Duration.days(3),
        },
        accountRecovery: cognito.AccountRecovery.EMAIL_ONLY,
    });
    
    const defaultGroup = new cognito.CfnUserPoolGroup(this, 'zeitplan-default-users', {
      userPoolId: userPool.userPoolId,
      groupName: 'zeitplan-default-users',
      description: 'Default group'
    })

    const googleClientSecret = sm.Secret.fromSecretAttributes(this, 'ZeitplanGoogleSecret', {
        secretCompleteArn: process.env.GOOGLE_SECRET_ARN,
    });

    const googleUserPool = new cognito.UserPoolIdentityProviderGoogle(this, 'zeitplanGoogleUserPool', {
        clientId: process.env.GOOGLE_CLIENT_ID ?? '',
        clientSecret: googleClientSecret.secretValue.unsafeUnwrap(),
        userPool: userPool,
        attributeMapping: {
            email: cognito.ProviderAttribute.GOOGLE_EMAIL,
            givenName: cognito.ProviderAttribute.GOOGLE_NAME,
        },
    });
    
    const webClient = userPool.addClient('web-client', {
      userPoolClientName: 'zeitplan-web-app',
      supportedIdentityProviders: [
        cognito.UserPoolClientIdentityProvider.GOOGLE,
      ],
      authFlows: {
        userSrp: true,
      }
    });
    
    const identityPool = new cognito.CfnIdentityPool(this, 'zeitplan-identity-pool', {
      identityPoolName: 'zeitplan-identity-pool',
      allowUnauthenticatedIdentities: true,
      cognitoIdentityProviders: [
        {
          clientId: webClient.userPoolClientId,
          providerName: userPool.userPoolProviderName
        }
      ]
    });

    // DynamoDB setup
    const userTable = new Table(this, 'user-table', {
      partitionKey: {
        name: 'userId',
        type: AttributeType.STRING
      },
      tableName: 'user',
      removalPolicy: RemovalPolicy.DESTROY
    });

    const calendarTable = new Table(this, 'calendar-table', {
      partitionKey: {
        name: 'calendarId',
        type: AttributeType.STRING,
      },
      tableName: 'calendar',
      removalPolicy: RemovalPolicy.DESTROY,
    });

    const meetingTable = new Table(this, 'meeting-table', {
      partitionKey: {
        name: 'meetingId',
        type: AttributeType.STRING,
      },
      tableName: 'meeting',
      removalPolicy: RemovalPolicy.DESTROY
    });

    
    // GraphQL API
    // App Sync
    
    const graphQL = new appsync.CfnGraphQLApi(this, 'Api', {
      name: 'zeitplan-graphql',
      authenticationType: 'AMAZON_COGNITO_USER_POOLS'
    });

    const graphqlSchema = new appsync.CfnGraphQLSchema(this, 'zeitplan-graphql-schema', {
      apiId: graphQL.attrApiId,
      definition: fs.readFileSync(path.join(__dirname, 'schema.graphql'), 'utf-8')
    });
    
    const userTableRole = new Role(this, 'UserDBRole', {
      assumedBy: new ServicePrincipal('appsync.amazonaws.com')
    });
    
    const meetingTableRole = new Role(this, 'MeetingDBRole', {
      assumedBy: new ServicePrincipal('appsync.amazonaws.com')
    });
    
    const calendarTableRole = new Role(this, 'CalendarDBRole', {
      assumedBy: new ServicePrincipal('appsync.amazonaws.com')
    });
    const calendarTableDataSource = new appsync.CfnDataSource(this, 'CalendarDataSource', {
      apiId: graphQL.attrApiId,
      name: 'CalendarDataSource',
      type: 'AMAZON_DYNAMODB',
      dynamoDbConfig: {
        tableName: calendarTable.tableName,
        awsRegion: this.region
      },
      serviceRoleArn: calendarTableRole.roleArn
    });

    const calendarInsertResolver = new appsync.CfnResolver(this, 'calendar-insert-resolver', {
      apiId: graphQL.attrApiId,
      typeName: 'Mutation',
      fieldName: 'addCalendar',
      dataSourceName: calendarTableDataSource.name,
      requestMappingTemplate: `{
        "version": "2022-01-08",
        "operation": "PutItem",
        "key": {
          "calendarId": { "$": "$util.autoId()" }
        },
        "attributeValues": {
          "owner": $util.dynamodb.toDynamoDBJson($context.identity.username),
          #foreach( $entry in $context.arguments.entrySet() )
            , "\${entry.key}": $util.dynamodb.toDynamoDBJson($entry.value)
          #end
        }
      }`,
      responseMappingTemplate: `$util.toJson($ctx.result)`
    });

    const calendarGetResolver = new appsync.CfnResolver(this, 'calendar-get-all-user-resolver', {
      apiId: graphQL.attrApiId,
      typeName: 'Query',
      fieldName: 'calendars',
      dataSourceName: calendarTableDataSource.name,
      requestMappingTemplate: `{
        "version": "2022-01-08",
        "operation": "Query",
        "query": {
          "expression" : "ownerId = :username",
          "expressionVa-index-index-indexlues": {
            ":username": $util.dynamodb.toDynamoDBJson($context.identity.username)
          }
        },
        "index": "owner"
      }`,
      responseMappingTemplate: `$util.toJson($ctx.result)`
    });

    /*
    // Cloudfront access setup here
    const zeitplanCloudfrontOAI = new cloudfront.OriginAccessIdentity(this, 'cloudfront-OAI', {
      comment: 'OAI for Zeitplan'
    });

    // Bucket for site declared here - no content deployed yet
    const zeitplanBucket = new s3.Bucket(this, 'ZeitplanBucket', {
      bucketName: 'zeitplan-web-bucket',
      publicReadAccess: true,
      removalPolicy: RemovalPolicy.DESTROY,
    });

    // Now we must give access to cloudfront to our bucket:
    zeitplanBucket.addToResourcePolicy(new iam.PolicyStatement({
      actions: ['s3:GetObject'],
      resources: [zeitplanBucket.arnForObjects('*')],
      principals: [new iam.CanonicalUserPrincipal(zeitplanCloudfrontOAI.cloudFrontOriginAccessIdentityS3CanonicalUserId)]
    }));

    // Setup cloudfront to our bucket
    const cloudfrontDistribution = new cloudfront.Distribution(this, 'Zeitplan Distribution', {
      defaultRootObject: 'index.html',
      minimumProtocolVersion: cloudfront.SecurityPolicyProtocol.TLS_V1_2_2021,
      errorResponses: [
        {
          httpStatus: 403,
          responseHttpStatus: 403,
          responsePagePath: '/error.html',
          ttl: Duration.minutes(30)
        }
      ],
      defaultBehavior: {
        origin: new cloudfront_origins.S3Origin(zeitplanBucket, { originAccessIdentity: zeitplanCloudfrontOAI }),
        compress: true,
        allowedMethods: cloudfront.AllowedMethods.ALLOW_GET_HEAD_OPTIONS,
        viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
      }
    });

    new s3Deploy.BucketDeployment(this, 'Deploy Zeitplan with Invalidation', {
      sources: [s3Deploy.Source.asset('../web/dist')],
      destinationBucket: zeitplanBucket,
      distribution: cloudfrontDistribution,
      distributionPaths: ['/*'],
    })

   */
  }
}
