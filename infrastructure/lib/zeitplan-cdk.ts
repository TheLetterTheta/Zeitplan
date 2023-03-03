import {
  Duration,
  RemovalPolicy,
  Stack,
  StackProps,
  CfnOutput,
  aws_route53,
  aws_cloudfront,
  aws_s3,
  aws_certificatemanager,
  aws_cloudfront_origins,
  aws_route53_targets,
  aws_s3_deployment,
  aws_appsync,
} from "aws-cdk-lib";
import { RustFunction } from "cargo-lambda-cdk";
import * as path from "path";
import * as fs from "fs";
import * as dotenv from "dotenv";
import { Construct } from "constructs";
import * as cognito from "aws-cdk-lib/aws-cognito";
import * as sm from "aws-cdk-lib/aws-secretsmanager";
import * as appsync from "aws-cdk-lib/aws-appsync";
import { AttributeType, Table } from "aws-cdk-lib/aws-dynamodb";
import {
  CanonicalUserPrincipal,
  PolicyStatement,
  Role,
  ServicePrincipal,
} from "aws-cdk-lib/aws-iam";
import {
  Code,
  Function,
  FunctionUrlAuthType,
  Runtime,
} from "aws-cdk-lib/aws-lambda";
import { UserPoolOperation } from "aws-cdk-lib/aws-cognito";

dotenv.config();

export class ZeitplanCdk extends Stack {
  constructor(scope: Construct, id: string, props?: StackProps) {
    super(scope, id, props);

    new CfnOutput(this, "region", {
      exportName: "region",
      value: this.region,
    });

    const time_interval = 30;
    const minutes_in_day = 60 * 24;
    const slots = minutes_in_day / time_interval;
    const creditCount = 10000;

    new CfnOutput(this, "interval", {
      exportName: "interval",
      value: `${time_interval}`,
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
        ],
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

    const scheduleTable = new Table(this, "schedule-table", {
      partitionKey: {
        name: "userId",
        type: AttributeType.STRING,
      },
      sortKey: {
        name: "created",
        type: AttributeType.NUMBER,
      },
      tableName: "zeitplan-schedules",
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

    const scheduleTableRole = new Role(this, "ScheduleDBRole", {
      assumedBy: new ServicePrincipal("appsync.amazonaws.com"),
    });
    scheduleTable.grantReadWriteData(scheduleTableRole);

    const transactionDeleteTableRole = new Role(
      this,
      "TransactionDeleteCalendarDBRole",
      {
        assumedBy: new ServicePrincipal("appsync.amazonaws.com"),
      }
    );
    calendarTable.grantWriteData(transactionDeleteTableRole);
    meetingTable.grantWriteData(transactionDeleteTableRole);

    const executePaymentRole = new Role(this, "ExecutePaymentRole", {
      assumedBy: new ServicePrincipal("appsync.amazonaws.com"),
    });

    const executeScheduleFunctionRole = new Role(
      this,
      "ExecuteScheduleFunctionRole",
      {
        assumedBy: new ServicePrincipal("appsync.amazonaws.com"),
      }
    );

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

    const calendarTransactionDataSource = new appsync.CfnDataSource(
      this,
      "calendar-transaction-datasource",
      {
        apiId: graphQL.attrApiId,
        name: "CalendarTransactionDataSource",
        type: "AMAZON_DYNAMODB",
        dynamoDbConfig: {
          tableName: "_empty_",
          awsRegion: this.region,
        },
        serviceRoleArn: transactionDeleteTableRole.roleArn,
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

    const getAffectedMeetingsFunction = new appsync.CfnFunctionConfiguration(
      this,
      "calendar-get-affected-meetings",
      {
        apiId: graphQL.attrApiId,
        dataSourceName: meetingTableDataSource.name,
        runtime: {
          name: "APPSYNC_JS",
          runtimeVersion: "1.0.0",
        },
        name: "GetCalendarAffectedMeetings",
        code: `
        import { util } from '@aws-appsync/utils';

        export function request(context) {
          const { name } = context.arguments;
          const { username } = context.identity;


          const query = JSON.parse(
            util.transform.toDynamoDBConditionExpression({ userId: { eq: username } })
          );

          const filter = JSON.parse(
            util.transform.toDynamoDBFilterExpression({ participants: { contains: name } })
          );

          return {
            operation: 'Query',
            query,
            filter
          }
        }

        export function response(context) {
          const deleted = [];
          const affected = [];

          for(let result of context.result.items) {
            if (result.participants.length === 1) {
              deleted.push(result);
            } else {
              affected.push(result);
            }
          }
          
          return {
            deleted,
            affected
          }
        }
        `,
      }
    );

    const deleteMeetingFunction = new appsync.CfnFunctionConfiguration(
      this,
      "calendar-delete-affected",
      {
        apiId: graphQL.attrApiId,
        name: "DeleteCalendarAndAffectedMeetings",
        runtime: {
          name: "APPSYNC_JS",
          runtimeVersion: "1.0.0",
        },
        dataSourceName: calendarTransactionDataSource.name,
        code: `
        import { util } from '@aws-appsync/utils';

        export function request(context) {
          const { affected, deleted } = context.prev.result;
          const { name } = context.arguments; 
          const { username } = context.identity;
        
          const transactions = [{
            table: "${calendarTable.tableName}",
            operation: "DeleteItem",
            key: util.dynamodb.toMapValues({ userId: username, name })
          }];

          for (let deleteItem of deleted) {
            transactions.push({
              table: "${meetingTable.tableName}",
              operation: "DeleteItem",
              key: util.dynamodb.toMapValues({ created: deleteItem.created, userId: username })
            });
          }


          for (let updateItem of affected) {
            transactions.push({
              table: "${meetingTable.tableName}",
              operation: "UpdateItem",
              key: util.dynamodb.toMapValues({ created: updateItem.created, userId: username }),
              update: {
                expression: "DELETE participants :participantName",
                expressionValues: { 
                  ':participantName': util.dynamodb.toStringSet([name])
                }
              }
            });
          }

          return {
            operation: "TransactWriteItems",
            transactItems: transactions
          };
        }

        export function response(context) {
          return context.result;
        }
        `,
      }
    );

    const calendarDeleteResolver = new appsync.CfnResolver(
      this,
      "calendar-delete-resolver",
      {
        apiId: graphQL.attrApiId,
        typeName: "Mutation",
        fieldName: "deleteCalendar",
        runtime: {
          name: "APPSYNC_JS",
          runtimeVersion: "1.0.0",
        },
        kind: "PIPELINE",
        pipelineConfig: {
          functions: [
            getAffectedMeetingsFunction.attrFunctionId,
            deleteMeetingFunction.attrFunctionId,
          ],
        },
        code: `
        import { util } from '@aws-appsync/utils';

        export function request(context) {
          return {};
        }

        export function response(context) {
          if (context.prev.error) {
            util.appendError(context.prev.error.message, context.prev.error.type, null, context.prev.result.cancellationReasons);
          }

          return context.prev.result.keys[0];
        }
        `,
      }
    );
    calendarDeleteResolver.addDependency(graphqlSchema);
    calendarDeleteResolver.addDependency(deleteMeetingFunction);
    calendarDeleteResolver.addDependency(getAffectedMeetingsFunction);

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
            "participants": $util.dynamodb.toStringSetJson($context.arguments.participants),
            "title": $util.dynamodb.toStringJson($context.arguments.title),
            "duration": $util.dynamodb.toNumberJson($context.arguments.duration),
          }
        }`,
        responseMappingTemplate: `$util.toJson($ctx.result)`,
      }
    );
    meetingInsertResolver.addDependency(graphqlSchema);

    const queryMeetingsByUserFunction = new appsync.CfnFunctionConfiguration(
      this,
      "meeting-query-by-user-function",
      {
        apiId: graphQL.attrApiId,
        name: "QueryMeetingsByUserId",
        dataSourceName: meetingTableDataSource.name,
        runtime: {
          name: "APPSYNC_JS",
          runtimeVersion: "1.0.0",
        },
        code: `
        import { util } from '@aws-appsync/utils'

        export function request(context) {
          const { username } = context.identity;
          
          const query = JSON.parse(
            util.transform.toDynamoDBConditionExpression({ userId: { eq: username } })
          );

          return {
            operation: 'Query',
            query
          }
        }

        export function response(context) {
          return context.result.items;
        }
        `,
      }
    );

    const meetingGetResolver = new appsync.CfnResolver(
      this,
      "meeting-get-all-user-resolver",
      {
        apiId: graphQL.attrApiId,
        typeName: "Query",
        fieldName: "meetings",
        kind: "PIPELINE",
        pipelineConfig: {
          functions: [queryMeetingsByUserFunction.attrFunctionId],
        },
        runtime: {
          name: "APPSYNC_JS",
          runtimeVersion: "1.0.0",
        },
        code: `
        import { util } from '@aws-appsync/utils';

        export function request(context) {
          return {}
        }

        export function response(context) {
          return context.prev.result;
        }
        `,
      }
    );
    meetingGetResolver.addDependency(graphqlSchema);
    meetingGetResolver.addDependency(queryMeetingsByUserFunction);

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

    const updatePaymentIntentLambda = new Function(
      this,
      "zeitplan-update-payment-intent",
      {
        functionName: "Zeitplan-Update-Payment-Intent",
        description:
          "Update a payment intent with a different credit amount",
        handler: "main",
        runtime: Runtime.GO_1_X,
        code: Code.fromAsset(
          path.join(__dirname, "../lambdas/update_payment_intent/main.zip")
        ),
        environment: {
          PAYMENT_TABLE_NAME: paymentsTable.tableName
        }
      }
    );
    updatePaymentIntentLambda.grantInvoke(executePaymentRole);
    paymentsTable.grantWriteData(updatePaymentIntentLambda);

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

    const updatePaymentDataSource = new appsync.CfnDataSource(
      this,
      "zeitplan-update-payment-data-source",
      {
        apiId: graphQL.attrApiId,
        name: "updatePaymentLambdaSource",
        type: "AWS_LAMBDA",
        lambdaConfig: {
          lambdaFunctionArn: updatePaymentIntentLambda.functionArn,
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

    const updatePaymentResolver = new appsync.CfnResolver(
      this,
      "update-payment-intent-resolver",
      {
        apiId: graphQL.attrApiId,
        typeName: "Mutation",
        fieldName: "updateCheckout",
        dataSourceName: updatePaymentDataSource.name,
        requestMappingTemplate: `{
          "version": "2018-05-29",
          "operation": "Invoke",
          "payload": {
            "credits": $context.arguments.credits,
            "paymentIntent": "$context.arguments.paymentIntent"
          }
        }`,
        responseMappingTemplate: `$util.toJson($ctx.result)`,
      }
    )
    updatePaymentResolver.addDependency(graphqlSchema);

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

    const getScheduleAvailabilityFunction =
      new appsync.CfnFunctionConfiguration(
        this,
        "zeitplan-get-schedule-availability-function",
        {
          apiId: graphQL.attrApiId,
          runtime: {
            name: "APPSYNC_JS",
            runtimeVersion: "1.0.0",
          },
          name: "GetAvailabilityInformation",
          dataSourceName: userTableDataSource.name,
          code: `
        import { util } from '@aws-appsync/utils';
        
        export function request(context) {
          if (context.arguments.credits < 1) {
            return util.error("Credits must be > 0", "BadRequest");
          }
          const { username } = context.identity;

          return {
            operation: "GetItem",
            key: util.dynamodb.toMapValues({ userId: username }),
            projection: {
              expression: "credits, events"
            }
          }
        }
        
        export function response(context) {
          const { events, credits } = context.result;

          if (credits === null || credits < context.arguments.credits) {
            return util.error("Not enough credits to schedule", "InsufficientCredits");
          }

          if (events === null) {
            return util.error("No availability to schedule against", "NoAvailability");
          }

          return { availability: events }
        }
        `,
        }
      );

    const getMeetingsForScheduleFunction = new appsync.CfnFunctionConfiguration(
      this,
      "zeitplan-schedule-get-meetings-function",
      {
        apiId: graphQL.attrApiId,
        runtime: {
          name: "APPSYNC_JS",
          runtimeVersion: "1.0.0",
        },
        name: "GetMeetingsForSchedule",
        dataSourceName: meetingTableDataSource.name,
        code: `
        import { util } from '@aws-appsync/utils';

        export function request(context) {
          const { username } = context.identity;

          const query = JSON.parse(
            util.transform.toDynamoDBConditionExpression({ userId: { eq: username } })
          );

          return {
            operation: 'Query',
            query
          }
        }

        export function response(context) {
          const { items } = context.result;

          if (items === null || items.length === 0) {
            return util.error("No meetings to schedule", "NoMeetings");
          }

          const { availability } = context.prev.result;

          const meetings = items.map((result) => ({
            id: result.created,
            participants: result.participants,
            duration: result.duration
          }));

          return { availability, meetings };
        }
        `,
      }
    );

    const getMeetingParticipants = new appsync.CfnFunctionConfiguration(
      this,
      "zeitplan-get-meeting-participants-function",
      {
        apiId: graphQL.attrApiId,
        runtime: {
          name: "APPSYNC_JS",
          runtimeVersion: "1.0.0",
        },
        name: "GetParticipantsBlockedTimes",
        dataSourceName: calendarTableDataSource.name,
        code: `
        import { util } from '@aws-appsync/utils';

        export function request(context) {
          const { username } = context.identity;
          const { meetings } = context.prev.result;

          const unique_participants = [];
          const getItems = [];

          for (let meeting of meetings ) {
            for (let id of meeting.participants) {
              if (unique_participants.every((i) => i !== id)) {
                unique_participants.push(id);
                getItems.push(util.dynamodb.toMapValues({ userId: username, name: id }))
              } 
            }
          }

          return {
            operation: 'BatchGetItem',
            tables: {
              "${calendarTable.tableName}": {
                keys: getItems
              }
            }
          }
        }

        export function response(context) {
          const items = context.result.data["${calendarTable.tableName}"];

          if (items === null) {
            return util.error("No participants for meetings", "NoParticipants");
          }

          const cleaned = items.filter((participant) => participant !== null);

          if (cleaned.length === 0) {
            return util.error("Could not find participants", "ParticipantsNotFound");
          }

          const participants = cleaned.map((participant) => {
            const events = participant.events.map((time) => [time.start, time.end]);

            const blockedEvents = participant.blockedDays.map((day) => {
              switch (day) {
                case 'Sunday':
                  return [1, ${slots * 1}];
                case 'Monday':
                  return [${slots * 1 + 1}, ${slots * 2}];
                case 'Tuesday':
                  return [${slots * 2 + 1}, ${slots * 3}];
                case 'Wednesday':
                  return [${slots * 3 + 1}, ${slots * 4}];
                case 'Thursday':
                  return [${slots * 4 + 1}, ${slots * 5}];
                case 'Friday':
                  return [${slots * 5 + 1}, ${slots * 6}];
                case 'Saturday':
                  return [${slots * 6 + 1}, ${slots * 7}];
              }
            });

            for (let event of blockedEvents) {
              events.push(event)
            }

            return { id: participant.name, events };
          })

          const { availability, meetings } = context.prev.result;

          const timeRangeAvailability = availability.map((time) => {
            return [ time.start, time.end ];
          });

          const meetingConfiguration = meetings.map((meeting) => ({
            id: \`\${meeting.id}\`,
            blockedTimes: meeting.participants.flatMap((id) => {
              return participants.find((participant) => participant.id == id).events;
            }),
            duration: meeting.duration
          }));

          return { availability: timeRangeAvailability, meetings: meetingConfiguration };
        }
        `,
      }
    );

    const scheduleFunction = new RustFunction(
      this,
      "zeitplan-schedule-meetings-function",
      {
        functionName: "Zeitplan-Schedule-Meetings",
        manifestPath: path.join(
          __dirname,
          "../lambdas/schedule_meetings"
        ),
        environment: {
          NUM_SHUFFLES: "10000",
          PER_THREAD: "45",
        },
        timeout: Duration.seconds(30),
        description: "Search for a way to fit the schedule"
      }
    );

    scheduleFunction.grantInvoke(executeScheduleFunctionRole);

    const scheduleFunctionDataSource = new appsync.CfnDataSource(
      this,
      "zeitplan-schedule-meetings-data-source",
      {
        apiId: graphQL.attrApiId,
        name: "scheduleFunctionLambda",
        type: "AWS_LAMBDA",
        lambdaConfig: {
          lambdaFunctionArn: scheduleFunction.functionArn,
        },
        serviceRoleArn: executeScheduleFunctionRole.roleArn,
      }
    );

    const scheduleFunctionResolverFunction =
      new appsync.CfnFunctionConfiguration(
        this,
        "zeitplan-schedule-meetings-resolver-function",
        {
          apiId: graphQL.attrApiId,
          runtime: {
            name: "APPSYNC_JS",
            runtimeVersion: "1.0.0",
          },
          name: "ScheduleMeetingLambda",
          dataSourceName: scheduleFunctionDataSource.name,
          code: `import { util } from '@aws-appsync/utils';

          export function request(context) {
            const schedule = context.prev.result;
            const { credits } = context.arguments;
  
            return {
              operation: 'Invoke',
              payload: { schedule, count: credits * 800 }
            }
          }
  
          export function response(context) {
            const { schedule, failed } = context.result;
            const error = context.error;

            if (error) {
              util.appendError(error.message, error.type, context.result);

              return { error, solution: schedule, failed }
            } else {

              const solution = [];
              for (let [id, val] of Object.entries(schedule)) {
                const time = { start: val[0], end: val[1] };
                solution.push({ id, time });
              }
    
              return { solution, failed };
            }
          }
        `,
        }
      );
    scheduleFunctionResolverFunction.addDependency(scheduleFunctionDataSource);

    const scheduleTableDataSource = new appsync.CfnDataSource(
      this,
      "zeitplan-schedule-table-data-source",
      {
        apiId: graphQL.attrApiId,
        name: "scheduleTabledataSource",
        type: "AMAZON_DYNAMODB",
        dynamoDbConfig: {
          tableName: scheduleTable.tableName,
          awsRegion: this.region,
        },
        serviceRoleArn: scheduleTableRole.roleArn,
      }
    );

    const saveScheduleFunction = new aws_appsync.CfnFunctionConfiguration(
      this,
      "zeitplan-save-schedule-function",
      {
        apiId: graphQL.attrApiId,
        runtime: {
          name: "APPSYNC_JS",
          runtimeVersion: "1.0.0",
        },
        name: "SaveScheduleFunction",
        dataSourceName: scheduleTableDataSource.name,
        code: `
        import { util } from '@aws-appsync/utils';

        export function request(context) {
          const schedule = context.prev.result;
          const { username } = context.identity;

          Object.assign({ error: context.error }, schedule);

          return {
            operation: 'PutItem',
            key: util.dynamodb.toMapValues({ userId: username, created: util.time.nowEpochMilliSeconds() }),
            attributeValues: util.dynamodb.toMapValues(schedule)
          }
        }

        export function response(context) {
          let item = context.result;
          item.error = item.error?.message;

          return context.result;
        }
        `,
      }
    );
    saveScheduleFunction.addDependency(scheduleTableDataSource);

    const getSchedulesFunction = new aws_appsync.CfnFunctionConfiguration(
      this,
      "zeitplan-get-schedules-function",
      {
        apiId: graphQL.attrApiId,
        runtime: {
          name: "APPSYNC_JS",
          runtimeVersion: "1.0.0",
        },
        name: "GetSchedulesFunction",
        dataSourceName: scheduleTableDataSource.name,
        code: `
        import { util } from '@aws-appsync/utils';

        export function request(context) {
          const { limit = 10, nextToken } = context.arguments;
          const { username } = context.identity;

          const query = JSON.parse(
            util.transform.toDynamoDBConditionExpression({ userId: { eq: username } })
          );

          return {
            operation: 'Query',
            query,
            limit,
            nextToken,
            scanIndexForward: false
          }
        }

        export function response(context) {
          const { items = [], nextToken } = context.result;

          const data = items.map((item) => ({ ...item, error: item.error?.message, schedule: item.solution }));

          return { data, nextToken };
        }
        `,
      }
    );
    getSchedulesFunction.addDependency(scheduleTableDataSource);

    const getSchedulesResolver = new aws_appsync.CfnResolver(
      this,
      "zeitplan-get-schedules-resolver",
      {
        apiId: graphQL.attrApiId,
        typeName: "Query",
        fieldName: "schedules",
        kind: "PIPELINE",
        runtime: {
          name: "APPSYNC_JS",
          runtimeVersion: "1.0.0",
        },
        pipelineConfig: {
          functions: [
            getSchedulesFunction.attrFunctionId,
          ],
        },
        code: `
        import { util } from '@aws-appsync/utils';

        export function request(context) {
          return {};
        }

        export function response(context) {
          const { data, nextToken } = context.prev.result;

          return { data, nextToken };
        }
        `,
      }
    );
    getSchedulesResolver.addDependency(graphqlSchema);
    getSchedulesResolver.addDependency(getSchedulesFunction);

    const deductCreditsFunction = new aws_appsync.CfnFunctionConfiguration(
      this,
      "zeitplan-deduct-credits-function",
      {
        apiId: graphQL.attrApiId,
        runtime: {
          name: "APPSYNC_JS",
          runtimeVersion: "1.0.0",
        },
        name: "DeductCreditsFunction",
        dataSourceName: userTableDataSource.name,
        code: `
        import { util } from '@aws-appsync/utils';

        export function request(context) {
          const { username } = context.identity;
          const { credits } = context.arguments;

          return {
            operation: 'UpdateItem',
            key: util.dynamodb.toMapValues({ userId: username }),
            update: {
              expression: "SET credits = credits - :deduct",
              expressionValues: { ":deduct": util.dynamodb.toNumber(credits) }
            }
          }
        }

        export function response(context) {
          return context.prev.result;
        }
        `,
      }
    );
    deductCreditsFunction.addDependency(userTableDataSource);

    const computeScheduleResolver = new appsync.CfnResolver(
      this,
      "zeitplan-compute-schedule-resolver",
      {
        apiId: graphQL.attrApiId,
        typeName: "Mutation",
        fieldName: "computeSchedule",
        kind: "PIPELINE",
        runtime: {
          name: "APPSYNC_JS",
          runtimeVersion: "1.0.0",
        },
        pipelineConfig: {
          functions: [
            getScheduleAvailabilityFunction.attrFunctionId,
            getMeetingsForScheduleFunction.attrFunctionId,
            getMeetingParticipants.attrFunctionId,
            scheduleFunctionResolverFunction.attrFunctionId,
            saveScheduleFunction.attrFunctionId,
            deductCreditsFunction.attrFunctionId,
          ],
        },
        code: `
        import { util } from '@aws-appsync/utils';

        export function request(context) {
          return {};
        }

        export function response(context) {
          const { failed, solution } = context.prev.result;

          return { failed, schedule: solution };
        }
        `,
      }
    );
    computeScheduleResolver.addDependency(graphqlSchema);
    computeScheduleResolver.addDependency(getScheduleAvailabilityFunction);
    computeScheduleResolver.addDependency(getMeetingsForScheduleFunction);
    computeScheduleResolver.addDependency(getMeetingParticipants);
    computeScheduleResolver.addDependency(scheduleFunctionResolverFunction);
    computeScheduleResolver.addDependency(saveScheduleFunction);
    computeScheduleResolver.addDependency(deductCreditsFunction);

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

    const cacheContentDays = 7;
    const cacheContentMinutes = cacheContentDays * 24 * 60;

    const cloudfrontHeaders = new aws_cloudfront.ResponseHeadersPolicy(
      this,
      "zeitplan-stripe-header-policy",
      {
        securityHeadersBehavior: {
          contentSecurityPolicy: {
            contentSecurityPolicy:
              "default-src 'self' www.zeitplan-app.com *.us-east-1.amazonaws.com; connect-src 'self' www.zeitplan-app.com https://zeitplan.auth.us-east-1.amazoncognito.com https://api.stripe.com https://maps.googleapis.com *.us-east-1.amazonaws.com;frame-src https://js.stripe.com https://hooks.stripe.com; script-src 'self' www.zeitplan-app.com https://js.stripe.com https://maps.googleapis.com; object-src 'none';",
            override: true,
          },
        },
        customHeadersBehavior: {
          customHeaders: [
            {
              header: "Cache-Control",
              override: true,
              value: `public, max-age=${cacheContentMinutes}`,
            },
          ],
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
            httpStatus: 403,
            responseHttpStatus: 200,
            responsePagePath: "/index.html",
            ttl: Duration.minutes(20),
          },
        ],
        defaultBehavior: {
          origin: new aws_cloudfront_origins.S3Origin(siteBucket, {
            originAccessIdentity: cloudfrontOAI,
          }),
          responseHeadersPolicy: cloudfrontHeaders,
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
