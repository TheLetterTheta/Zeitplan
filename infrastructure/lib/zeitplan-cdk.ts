import {
  aws_dynamodb,
  Duration,
  lambda_layer_awscli,
  RemovalPolicy,
  Stack,
  StackProps,
  CfnOutput,
  aws_pinpoint,
  aws_route53,
  aws_cloudfront,
  aws_s3,
  aws_certificatemanager,
  aws_cloudfront_origins,
  aws_route53_targets,
  aws_s3_deployment,
} from "aws-cdk-lib";
import * as path from "path";
import * as fs from "fs";
import * as dotenv from "dotenv";
import { Construct, Node } from "constructs";
import * as cognito from "aws-cdk-lib/aws-cognito";
import * as sm from "aws-cdk-lib/aws-secretsmanager";
import * as appsync from "aws-cdk-lib/aws-appsync";
import { AttributeType, Table } from "aws-cdk-lib/aws-dynamodb";
import {
  CanonicalUserPrincipal,
  Effect,
  Group,
  ManagedPolicy,
  Policy,
  PolicyStatement,
  Role,
  ServicePrincipal,
} from "aws-cdk-lib/aws-iam";
import { LambdaFunction } from "aws-cdk-lib/aws-events-targets";
import {
  Code,
  FilterCriteria,
  FilterRule,
  Function,
  FunctionUrlAuthType,
  Runtime,
  StartingPosition,
} from "aws-cdk-lib/aws-lambda";
import {
  CfnIdentityPoolRoleAttachment,
  UserPoolIdentityProviderGoogle,
  UserPoolOperation,
} from "aws-cdk-lib/aws-cognito";
import { env } from "process";
import { AuthType } from "aws-cdk-lib/aws-stepfunctions-tasks";
import { DynamoEventSource } from "aws-cdk-lib/aws-lambda-event-sources";
import { CloudFrontAllowedCachedMethods } from "aws-cdk-lib/aws-cloudfront";
import { IamResource } from "aws-cdk-lib/aws-appsync";
import { DnsValidatedCertificate } from "aws-cdk-lib/aws-certificatemanager";
import { Certificate } from "crypto";
import { S3 } from "aws-cdk-lib/aws-ses-actions";

dotenv.config();

export class ZeitplanCdk extends Stack {
  constructor(scope: Construct, id: string, props?: StackProps) {
    super(scope, id, props);

    new CfnOutput(this, "region", {
      exportName: "region",
      value: this.region,
    });

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

    const userPoolDomain = userPool.addDomain("zeitplan-hosted-ui", {
      cognitoDomain: {
        domainPrefix: "zeitplan",
      },
    });

    new CfnOutput(this, "HostedUiDomain", {
      value: userPoolDomain.baseUrl(),
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
        clientSecretValue: googleClientSecret.secretValue,
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
      oAuth: {
        callbackUrls: [
          "https://localhost:1234/schedule",
          "https://www.zeitplan-app.com/schedule",
        ],
        logoutUrls: [
          "https://localhost:1234/",
          "https://www.zeitplan-app.com/",
        ]
      },
      supportedIdentityProviders: [
        {
          name: "Google",
        },
      ],
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

    new CfnOutput(this, "user-pool-id", {
      exportName: "user-pool-id",
      value: userPool.userPoolId,
    });
    new CfnOutput(this, "webclient-id", {
      exportName: "webclient-id",
      value: webClient.userPoolClientId,
    });

    // DynamoDB setup
    const userTable = new Table(this, "user-table", {
      partitionKey: {
        name: "userId",
        type: AttributeType.STRING,
      },
      tableName: "zeitplan-user",
      removalPolicy: RemovalPolicy.DESTROY,
      // stream: aws_dynamodb.StreamViewType.NEW_IMAGE,
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
        name: "orderId",
        type: AttributeType.STRING,
      },
      tableName: "zeitplan-payment-order",
      removalPolicy: RemovalPolicy.DESTROY,
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
      additionalAuthenticationProviders: [
        {
          authenticationType: "API_KEY",
        },
      ],
    });

    new CfnOutput(this, "graphql-api-endpoint", {
      exportName: "graphql-api-endpoint",
      value: graphQL.attrGraphQlUrl,
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
      assumedBy: new ServicePrincipal("appsync.amazonaws.com"),
    });

    // GQL RESOLVERS
    //

    const noDataSource = new appsync.CfnDataSource(this, "NoOpDataSource", {
      apiId: graphQL.attrApiId,
      name: "NoOpDataSource",
      type: "NONE",
    });

    const creditsChangedResolver = new appsync.CfnResolver(
      this,
      "credits-changed-resolver",
      {
        apiId: graphQL.attrApiId,
        typeName: "Mutation",
        fieldName: "creditsChanged",
        dataSourceName: noDataSource.name,
        requestMappingTemplate: `{         
          "version": "2018-05-29",
          "payload": $util.toJson($context.args)
        }`,
        responseMappingTemplate: "$context.args.credits",
      }
    );
    creditsChangedResolver.addDependency(graphqlSchema);
    creditsChangedResolver.addDependency(noDataSource);

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
          "events": $util.dynamodb.toListJson($context.arguments.events),
          "blockedDays": $util.dynamodb.toListJson($context.arguments.blockedDays)
        }
      }`,
        responseMappingTemplate: `$util.toJson($ctx.result)`,
      }
    );
    calendarInsertResolver.addDependency(graphqlSchema);

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
    calendarGetResolver.addDependency(graphqlSchema);

    const calendarDeleteResolver = new appsync.CfnResolver(
      this,
      "calendar-delete-resolver",
      {
        apiId: graphQL.attrApiId,
        typeName: "Mutation",
        fieldName: "deleteCalendar",
        dataSourceName: calendarTableDataSource.name,
        requestMappingTemplate: `{
          "version": "2018-05-29",
          "operation": "DeleteItem",
          "key": {
            "userId": $util.dynamodb.toDynamoDBJson($context.identity.username),
            "name": $util.dynamodb.toDynamoDBJson($ctx.arguments.name)
          }
        }`,
        responseMappingTemplate: `$util.toJson($ctx.result)`,
      }
    );
    calendarDeleteResolver.addDependency(graphqlSchema);

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
        requestMappingTemplate: `{
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
    meetingInsertResolver.addDependency(graphqlSchema);

    const meetingGetResolver = new appsync.CfnResolver(
      this,
      "meeting-get-all-user-resolver",
      {
        apiId: graphQL.attrApiId,
        typeName: "Query",
        fieldName: "meetings",
        dataSourceName: meetingTableDataSource.name,
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
        responseMappingTemplate: `$util.toJson($util.list.sortList($ctx.result.items, false, "created"))`,
      }
    );
    meetingGetResolver.addDependency(graphqlSchema);

    const meetingDeleteResolver = new appsync.CfnResolver(
      this,
      "meeting-delete-resolver",
      {
        apiId: graphQL.attrApiId,
        typeName: "Mutation",
        fieldName: "deleteMeeting",
        dataSourceName: meetingTableDataSource.name,
        requestMappingTemplate: `{
          "version": "2018-05-29",
          "operation": "DeleteItem",
          "key": {
            "userId": $util.dynamodb.toDynamoDBJson($context.identity.username),
            "created": $util.dynamodb.toDynamoDBJson($ctx.arguments.created)
          }
        }`,
        responseMappingTemplate: `$util.toJson($ctx.result)`,
      }
    );
    meetingDeleteResolver.addDependency(graphqlSchema);

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
    userGetResolver.addDependency(graphqlSchema);

    const userInsertResolver = new appsync.CfnResolver(
      this,
      "user-events-insert-resolver",
      {
        apiId: graphQL.attrApiId,
        typeName: "Mutation",
        fieldName: "saveEvents",
        dataSourceName: userTableDataSource.name,
        requestMappingTemplate: `{
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
    userInsertResolver.addDependency(graphqlSchema);

    const createUserCode = new Function(this, "zeitplan-create-user", {
      functionName: "Zeitplan-Create-User",
      description: "Trigger post user signup to create a new user",
      handler: "main",
      runtime: Runtime.GO_1_X,
      code: Code.fromAsset(
        path.join(__dirname, "../lambdas/create_user/main.zip")
      ),
      environment: {
        DEFAULT_CREDITS: "20",
        USER_TABLE_NAME: userTable.tableName,
      },
    });

    userTable.grantWriteData(createUserCode);

    userPool.addTrigger(UserPoolOperation.POST_CONFIRMATION, createUserCode);

    const createPaymentIntentLambda = new Function(
      this,
      "zeitplan-create-payment-intent",
      {
        functionName: "Zeitplan-Create-Payment-Intent",
        description:
          "Integration with payment service to initiate a checkout session",
        handler: "main",
        runtime: Runtime.GO_1_X,
        code: Code.fromAsset(
          path.join(__dirname, "../lambdas/create_payment_intent/main.zip")
        ),
        environment: {
          PAYMENT_TABLE_NAME: paymentsTable.tableName,
        },
      }
    );
    createPaymentIntentLambda.grantInvoke(executePaymentRole);
    paymentsTable.grantWriteData(createPaymentIntentLambda);

    const createPaymentDataSource = new appsync.CfnDataSource(
      this,
      "zeitplan-create-payment-data-source",
      {
        apiId: graphQL.attrApiId,
        name: "createPaymentLambdaSource",
        type: "AWS_LAMBDA",
        lambdaConfig: {
          lambdaFunctionArn: createPaymentIntentLambda.functionArn,
        },
        serviceRoleArn: executePaymentRole.roleArn,
      }
    );

    const createPaymentResolver = new appsync.CfnResolver(
      this,
      "create-payment-intent-resolver",
      {
        apiId: graphQL.attrApiId,
        typeName: "Mutation",
        fieldName: "beginCheckout",
        dataSourceName: createPaymentDataSource.name,
        requestMappingTemplate: `{
          "version": "2018-05-29",
          "operation": "Invoke",
          "payload": {
            "credits": $context.arguments.credits,
            "userId": "$context.identity.username"
          }
        }`,
        responseMappingTemplate: `$util.toJson($ctx.result)`,
      }
    );
    createPaymentResolver.addDependency(graphqlSchema);

    const creditsCreatedSubscriptionResolver = new appsync.CfnResolver(
      this,
      "credits-changed-subscription-resolver",
      {
        apiId: graphQL.attrApiId,
        typeName: "Subscription",
        fieldName: "onCreditsChanged",
        dataSourceName: noDataSource.name,
        requestMappingTemplate: `{
          "version": "2018-05-29",
          "payload": { }
        }`,
        responseMappingTemplate: `
        $extensions.setSubscriptionFilter({
          "filterGroup": [
            {
              "filters": [
                {
                  "fieldName": "userId",
                  "operator": "eq",
                  "value": $ctx.identity.username
                }
              ]
            }
          ]
        })
        $util.toJson($context.result)
        `,
      }
    );

    const stripeWebhookLambda = new Function(this, "zeitplan-stripe-webhook", {
      functionName: "Zeitplan-Stripe-Webhook",
      description: "Stripe's webhook integration via HTTP request.",
      handler: "main",
      runtime: Runtime.GO_1_X,
      code: Code.fromAsset(
        path.join(__dirname, "../lambdas/stripe_webhook/main.zip")
      ),
      environment: {
        PAYMENT_TABLE_NAME: paymentsTable.tableName,
        USER_TABLE_NAME: userTable.tableName,
      },
    });
    paymentsTable.grantReadWriteData(stripeWebhookLambda);
    userTable.grantWriteData(stripeWebhookLambda);

    const stripeLambdaUrl = stripeWebhookLambda.addFunctionUrl({
      authType: FunctionUrlAuthType.NONE,
    });

    const userDbStreamLambda = new Function(
      this,
      "zeitplan-user-db-stream-process",
      {
        functionName: "Zeitplan-Process-User-DB-Stream",
        description:
          "Handler for DynamoDB Streams event to trigger AppSync mutation",
        handler: "main",
        runtime: Runtime.GO_1_X,
        code: Code.fromAsset(
          path.join(__dirname, "../lambdas/user_db_stream/main.zip")
        ),
        environment: {
          GQL_URL: graphQL.attrGraphQlUrl,
        },
      }
    );

    /*
    userDbStreamLambda.addEventSource(
      new DynamoEventSource(userTable, {
        startingPosition: StartingPosition.LATEST,
        maxRecordAge: Duration.minutes(5),
        filters: [
          FilterCriteria.filter({ eventName: FilterRule.isEqual("MODIFY") }),
        ],
      })
    );
    */

    const route53Zone = aws_route53.HostedZone.fromLookup(
      this,
      "zeitplan-hosted-zone",
      {
        domainName: process.env.REGISTERED_DOMAIN_NAME ?? "",
      }
    );
    const siteDomain = `${process.env.SUBDOMAIN}.${process.env.REGISTERED_DOMAIN_NAME}`;
    const cloudfrontOAI = new aws_cloudfront.OriginAccessIdentity(
      this,
      "zeitplan-cloudfront-oai",
      {
        comment: "OAI for Zeitplan",
      }
    );

    new CfnOutput(this, "HostedSiteUrl", { value: siteDomain });

    const siteBucket = new aws_s3.Bucket(this, "ZeitplanWebBucket", {
      bucketName: siteDomain,
      publicReadAccess: false,
      blockPublicAccess: aws_s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    siteBucket.addToResourcePolicy(
      new PolicyStatement({
        actions: ["s3:GetObject"],
        resources: [siteBucket.arnForObjects("*")],
        principals: [
          new CanonicalUserPrincipal(
            cloudfrontOAI.cloudFrontOriginAccessIdentityS3CanonicalUserId
          ),
        ],
      })
    );

    const certificate = new aws_certificatemanager.Certificate(
      this,
      "zeitplan-deploy-cert",
      {
        domainName: siteDomain,
        validation: {
          method: aws_certificatemanager.ValidationMethod.DNS,
          props: {
            hostedZone: route53Zone,
          },
        },
      }
    );

    const stripeCspHeaders = new aws_cloudfront.ResponseHeadersPolicy(
      this,
      "zeitplan-stripe-header-policy",
      {
        securityHeadersBehavior: {
          contentSecurityPolicy: {
            contentSecurityPolicy:
              "default-src 'self' www.zeitplan-app.com *.us-east-1.amazonaws.com; connect-src 'self' www.zeitplan-app.com https://api.stripe.com https://maps.googleapis.com *.us-east-1.amazonaws.com;frame-src https://js.stripe.com https://hooks.stripe.com; script-src 'self' www.zeitplan-app.com https://js.stripe.com https://maps.googleapis.com; object-src 'none';",
            override: true,
          },
        },
      }
    );

    const distribution = new aws_cloudfront.Distribution(
      this,
      "zeitplan-distribution",
      {
        certificate,
        defaultRootObject: "index.html",
        priceClass: aws_cloudfront.PriceClass.PRICE_CLASS_100,
        domainNames: [siteDomain],
        minimumProtocolVersion:
          aws_cloudfront.SecurityPolicyProtocol.TLS_V1_2_2021,
        errorResponses: [
          {
            httpStatus: 404,
            responseHttpStatus: 404,
            responsePagePath: "/index.html",
            ttl: Duration.minutes(20),
          },
          {
            httpStatus: 403,
            responseHttpStatus: 403,
            responsePagePath: "/index.html",
            ttl: Duration.minutes(20),
          },
        ],
        defaultBehavior: {
          origin: new aws_cloudfront_origins.S3Origin(siteBucket, {
            originAccessIdentity: cloudfrontOAI,
          }),
          responseHeadersPolicy: stripeCspHeaders,
          compress: true,
          allowedMethods: aws_cloudfront.AllowedMethods.ALLOW_GET_HEAD_OPTIONS,
          viewerProtocolPolicy:
            aws_cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
        },
      }
    );

    new aws_route53.ARecord(this, "zeitplan-a-record-registration", {
      recordName: siteDomain,
      target: aws_route53.RecordTarget.fromAlias(
        new aws_route53_targets.CloudFrontTarget(distribution)
      ),
      zone: route53Zone,
    });

    new aws_s3_deployment.BucketDeployment(this, "zeitplan-bucket-deployment", {
      sources: [
        aws_s3_deployment.Source.asset(path.join("dist/dist-deploy.zip")),
      ],
      destinationBucket: siteBucket,
      distribution,
      distributionPaths: ["/*"],
    });
  }
}
