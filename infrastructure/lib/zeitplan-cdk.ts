import {
  aws_dynamodb,
  Duration,
  lambda_layer_awscli,
  RemovalPolicy,
  Stack,
  StackProps,
} from "aws-cdk-lib";
import * as path from "path";
import * as fs from "fs";
import * as dotenv from "dotenv";
import { Construct, Node } from "constructs";
import * as cognito from "aws-cdk-lib/aws-cognito";
import * as sm from "aws-cdk-lib/aws-secretsmanager";
import * as appsync from "aws-cdk-lib/aws-appsync";
import { AttributeType, Table } from "aws-cdk-lib/aws-dynamodb";
import { ManagedPolicy, Role, ServicePrincipal } from "aws-cdk-lib/aws-iam";
import { LambdaFunction } from "aws-cdk-lib/aws-events-targets";
import { Code, Function, Runtime } from "aws-cdk-lib/aws-lambda";
import { UserPoolOperation } from "aws-cdk-lib/aws-cognito";

dotenv.config();

export class ZeitplanCdk extends Stack {
  constructor(scope: Construct, id: string, props?: StackProps) {
    super(scope, id, props);

    // AWS Cognito setup:
    const userPool = new cognito.UserPool(this, "zeitplanUserPool", {
      userPoolName: "zeitplan-userpool",
      selfSignUpEnabled: true,
      userVerification: {
        emailSubject: "Verify your email for Zeitplan",
        emailBody:
          "Thank you for signing up for Zeitplan! Your verification code is {####}",
        emailStyle: cognito.VerificationEmailStyle.CODE,
      },
      userInvitation: {
        emailSubject: "You've been invited to join Zeitplan!",
        emailBody:
          "Hello {username}, you have been invited to join Zeitplan. Your temporary password is {####}",
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

    const defaultGroup = new cognito.CfnUserPoolGroup(
      this,
      "zeitplan-default-users",
      {
        userPoolId: userPool.userPoolId,
        groupName: "zeitplan-default-users",
        description: "Default group",
      }
    );

    const googleClientSecret = sm.Secret.fromSecretAttributes(
      this,
      "ZeitplanGoogleSecret",
      {
        secretCompleteArn: process.env.GOOGLE_SECRET_ARN,
      }
    );

    const googleUserPool = new cognito.UserPoolIdentityProviderGoogle(
      this,
      "zeitplanGoogleUserPool",
      {
        clientId: process.env.GOOGLE_CLIENT_ID ?? "",
        clientSecret: googleClientSecret.secretValue.unsafeUnwrap(),
        userPool: userPool,
        attributeMapping: {
          email: cognito.ProviderAttribute.GOOGLE_EMAIL,
          givenName: cognito.ProviderAttribute.GOOGLE_NAME,
        },
      }
    );
    userPool.registerIdentityProvider(googleUserPool);

    const webClient = userPool.addClient("web-client", {
      userPoolClientName: "zeitplan-web-app",
      authFlows: {
        userSrp: true,
      },
    });

    const identityPool = new cognito.CfnIdentityPool(
      this,
      "zeitplan-identity-pool",
      {
        identityPoolName: "zeitplan-identity-pool",
        allowUnauthenticatedIdentities: true,
        cognitoIdentityProviders: [
          {
            clientId: webClient.userPoolClientId,
            providerName: userPool.userPoolProviderName,
          },
        ],
      }
    );

    // DynamoDB setup
    const userTable = new Table(this, "user-table", {
      partitionKey: {
        name: "userId",
        type: AttributeType.STRING,
      },
      tableName: "zeitplan-user",
      removalPolicy: RemovalPolicy.DESTROY,
    });

    const calendarTable = new Table(this, "calendar-table", {
      partitionKey: {
        name: "userId",
        type: AttributeType.STRING,
      },
      sortKey: {
        name: "name",
        type: AttributeType.STRING,
      },
      tableName: "zeitplan-calendar",
      removalPolicy: RemovalPolicy.DESTROY,
    });

    const meetingTable = new Table(this, "meeting-table", {
      partitionKey: {
        name: "userId",
        type: AttributeType.STRING,
      },
      sortKey: {
        name: "created",
        type: AttributeType.NUMBER,
      },
      tableName: "zeitplan-meeting",
      removalPolicy: RemovalPolicy.DESTROY,
    });
    
    const paymentsTable = new Table(this, "payments-table", {
      partitionKey: {
        name: "clientSecret",
        type: AttributeType.STRING,
      },
      tableName: "zeitplan-payments",
      removalPolicy: RemovalPolicy.DESTROY
    });
    
    // GraphQL API
    // App Sync

    const graphQL = new appsync.CfnGraphQLApi(this, "zeitplan-graphql-api", {
      name: "zeitplan-graphql",
      authenticationType: "AMAZON_COGNITO_USER_POOLS",
      userPoolConfig: {
        userPoolId: userPool.userPoolId,
        awsRegion: this.region,
        defaultAction: "ALLOW",
      },
    });

    const graphqlSchema = new appsync.CfnGraphQLSchema(
      this,
      "zeitplan-graphql-schema",
      {
        apiId: graphQL.attrApiId,
        definition: fs.readFileSync(
          path.join(__dirname, "schema.graphql"),
          "utf-8"
        ),
      }
    );

    const userTableRole = new Role(this, "UserDBRole", {
      assumedBy: new ServicePrincipal("appsync.amazonaws.com"),
    });
    userTable.grantReadWriteData(userTableRole);

    const meetingTableRole = new Role(this, "MeetingDBRole", {
      assumedBy: new ServicePrincipal("appsync.amazonaws.com"),
    });
    meetingTable.grantReadWriteData(meetingTableRole);

    const calendarTableRole = new Role(this, "CalendarDBRole", {
      assumedBy: new ServicePrincipal("appsync.amazonaws.com"),
    });
    calendarTable.grantReadWriteData(calendarTableRole);

    const executePaymentRole = new Role(this, "ExecutePaymentRole", {
      assumedBy: new ServicePrincipal("appsync.amazonaws.com")
    });

    // GQL RESOLVERS

    const calendarTableDataSource = new appsync.CfnDataSource(
      this,
      "CalendarDataSource",
      {
        apiId: graphQL.attrApiId,
        name: "CalendarDataSource",
        type: "AMAZON_DYNAMODB",
        dynamoDbConfig: {
          tableName: calendarTable.tableName,
          awsRegion: this.region,
        },
        serviceRoleArn: calendarTableRole.roleArn,
      }
    );

    const calendarInsertResolver = new appsync.CfnResolver(
      this,
      "calendar-insert-resolver",
      {
        apiId: graphQL.attrApiId,
        typeName: "Mutation",
        fieldName: "saveCalendar",
        dataSourceName: calendarTableDataSource.name,
        requestMappingTemplate: `{
        "version": "2018-05-29",
        "operation": "PutItem",
        "key": {
          "userId": $util.dynamodb.toStringJson($context.identity.username),
          "name": $util.dynamodb.toStringJson($context.arguments.name)
        },
        "attributeValues": {
          "events": $util.dynamodb.toListJson($context.arguments.events)
        }
      }`,
        responseMappingTemplate: `$util.toJson($ctx.result)`,
      }
    );
    calendarInsertResolver.addDependsOn(graphqlSchema);

    const calendarGetResolver = new appsync.CfnResolver(
      this,
      "calendar-get-all-user-resolver",
      {
        apiId: graphQL.attrApiId,
        typeName: "Query",
        fieldName: "calendars",
        dataSourceName: calendarTableDataSource.name,
        requestMappingTemplate: `{
        "version": "2018-05-29",
        "operation": "Query",
        "query": {
          "expression" : "#userId = :userId",
          "expressionNames": {
            "#userId": "userId",
          },
          "expressionValues": {
            ":userId": $util.dynamodb.toStringJson($context.identity.username)
          }
        }
      }`,
        responseMappingTemplate: `$util.toJson($util.list.sortList($ctx.result.items, false, "name"))`,
      }
    );
    calendarGetResolver.addDependsOn(graphqlSchema);

    const meetingTableDataSource = new appsync.CfnDataSource(
      this,
      "MeetingDataSource",
      {
        apiId: graphQL.attrApiId,
        name: "MeetingDataSource",
        type: "AMAZON_DYNAMODB",
        dynamoDbConfig: {
          tableName: meetingTable.tableName,
          awsRegion: this.region,
        },
        serviceRoleArn: meetingTableRole.roleArn,
      }
    );

    const meetingInsertResolver = new appsync.CfnResolver(
      this,
      "meeting-insert-resolver",
      {
        apiId: graphQL.attrApiId,
        typeName: "Mutation",
        fieldName: "saveMeeting",
        dataSourceName: meetingTableDataSource.name,
        requestMappingTemplate: 
        `{
          "version": "2018-05-29",
          "operation": "PutItem",
          "key": {
            "userId": $util.dynamodb.toStringJson($context.identity.username),
            "created": $util.dynamodb.toNumberJson($util.defaultIfNull($context.arguments.created, $util.time.nowEpochMilliSeconds()))
          },
          "attributeValues": {
            "participants": $util.dynamodb.toListJson($context.arguments.participants),
            "title": $util.dynamodb.toStringJson($context.arguments.title),
            "duration": $util.dynamodb.toNumberJson($context.arguments.duration),
          }
        }`,
        responseMappingTemplate: `$util.toJson($ctx.result)`,
      }
    );
    meetingInsertResolver.addDependsOn(graphqlSchema);

    const meetingGetResolver = new appsync.CfnResolver(
      this,
      "meeting-get-all-user-resolver",
      {
        apiId: graphQL.attrApiId,
        typeName: "Query",
        fieldName: "meetings",
        dataSourceName: meetingTableDataSource.name,
        requestMappingTemplate: 
        `{
          "version": "2018-05-29",
          "operation": "Query",
          "query": {
            "expression" : "#userId = :userId",
            "expressionNames": {
              "#userId": "userId",
            },
            "expressionValues": {
              ":userId": $util.dynamodb.toStringJson($context.identity.username)
            }
          }
        }`,
        responseMappingTemplate: `$util.toJson($util.list.sortList($ctx.result.items, false, "created"))`,
      }
    );
    meetingGetResolver.addDependsOn(graphqlSchema);

    const userTableDataSource = new appsync.CfnDataSource(
      this,
      "UserDataSource",
      {
        apiId: graphQL.attrApiId,
        name: "userDataSource",
        type: "AMAZON_DYNAMODB",
        dynamoDbConfig: {
          tableName: userTable.tableName,
          awsRegion: this.region,
        },
        serviceRoleArn: userTableRole.roleArn,
      }
    );

    const userGetResolver = new appsync.CfnResolver(this, "user-get-resolver", {
      apiId: graphQL.attrApiId,
      typeName: "Query",
      fieldName: "user",
      dataSourceName: userTableDataSource.name,
      requestMappingTemplate: `{
        "version": "2018-05-29",
        "operation": "GetItem",
        "key": {
          "userId": $util.dynamodb.toStringJson($context.identity.username)
        }
      }`,
      responseMappingTemplate: `$util.toJson($ctx.result)`,
    });
    userGetResolver.addDependsOn(graphqlSchema);

    const userInsertResolver = new appsync.CfnResolver(
      this,
      "user-events-insert-resolver",
      {
        apiId: graphQL.attrApiId,
        typeName: "Mutation",
        fieldName: "saveEvents",
        dataSourceName: userTableDataSource.name,
        requestMappingTemplate: 
        `{
          "version": "2018-05-29",
          "operation": "UpdateItem",
          "key": {
            "userId": $util.dynamodb.toStringJson($context.identity.username),
          },
          "update": {
            "expression": "SET events = :events",
            "expressionValues": {
              ":events": $util.dynamodb.toListJson($context.arguments.events)
            }
          }
        }`,
        responseMappingTemplate: `$util.toJson($ctx.result.events)`,
      }
    );
    userInsertResolver.addDependsOn(graphqlSchema);
    
    
    const createUserCode = new Function(this, "zeitplan-create-user", {
      functionName: "Zeitplan-Create-User",
      description: "Trigger post user signup to create a new user",
      handler: "main",
      runtime: Runtime.GO_1_X,
      code: Code.fromAsset(path.join(__dirname, "../lambdas/create_user/main.zip")),
      environment: {
        'DEFAULT_CREDITS': "20",
        'USER_TABLE_NAME': userTable.tableName
      }
    });
    
    userTable.grantWriteData(createUserCode);

    userPool.addTrigger(UserPoolOperation.POST_CONFIRMATION, createUserCode);

    const createPaymentIntentLambda = new Function(this, "zeitplan-create-payment-intent", {
      functionName: "Zeitplan-Create-Payment-Intent",
      description: "Integration with payment service to initiate a checkout session",
      handler: "main",
      runtime: Runtime.GO_1_X,
      code: Code.fromAsset(path.join(__dirname, "../lambdas/create_payment_intent/main.zip")),
      environment: {
        'PAYMENT_TABLE_NAME': paymentsTable.tableName
      }
    });
   createPaymentIntentLambda.grantInvoke(executePaymentRole); 
   paymentsTable.grantWriteData(createPaymentIntentLambda);
    
    const createPaymentDataSource = new appsync.CfnDataSource(this, "zeitplan-create-payment-data-source", {
      apiId: graphQL.attrApiId,
      name: "createPaymentLambdaSource",
      type: "AWS_LAMBDA",
      lambdaConfig: {
        lambdaFunctionArn: createPaymentIntentLambda.functionArn
      },
      serviceRoleArn: executePaymentRole.roleArn,
    })
    
    const createPaymentResolver = new appsync.CfnResolver(
      this,
      "create-payment-intent-resolver",
      {
        apiId: graphQL.attrApiId,
        typeName: "Mutation",
        fieldName: "beginCheckout",
        dataSourceName: createPaymentDataSource.name,
        requestMappingTemplate: 
        `{
          "version": "2018-05-29",
          "operation": "Invoke",
          "payload": {
            "credits": "$context.arguments.credits",
            "userId": "$context.identity.username"
          }
        }`,
        responseMappingTemplate: `$util.toJson($ctx.result)`,
      }
    );
    createPaymentResolver.addDependsOn(graphqlSchema);

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
