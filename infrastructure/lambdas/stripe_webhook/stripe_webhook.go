package main

import (
	"context"
	"encoding/json"
	"errors"
	"log"
	"os"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/feature/dynamodb/attributevalue"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
	stripe "github.com/stripe/stripe-go"
	"github.com/stripe/stripe-go/webhook"
)

var (
	endpointSecret  string
	stripeSecretKey string
)

type Request struct {
	Type string `json:"type"`
	Data []byte `json:"data"`
}

type PaymentKey struct {
	OrderId string `dynamodbav:"orderId"`
}

type PaymentValues struct {
	UserId  string `dynamodbav:"userId"`
	Credits int    `dynamodbav:"credits"`
}

type UserKey struct {
	UserId string `dynamodbav:"userId"`
}

type UserKeyUpdate struct {
	Credits int `dynamodbav:":credits"`
}

type CompleteUpdate struct {
	Complete bool `dynamodbav:":complete"`
}

func HandleRequest(ctx context.Context, req events.LambdaFunctionURLRequest) error {
	event, err := webhook.ConstructEvent([]byte(req.Body), req.Headers["stripe-signature"], endpointSecret)

	if err != nil {
		log.Println("Could not verify request")
		return errors.New("InvalidRequest")
	}

	switch event.Type {
	case "payment_intent.succeeded":
		var paymentIntent stripe.PaymentIntent
		err := json.Unmarshal(event.Data.Raw, &paymentIntent)

		if err != nil {
			log.Println("Could not parse Payment Intent")
			return err
		}

		if paymentIntent.Currency != "usd" {
			log.Println("Currency must be USD")
			return errors.New("InvalidCurrency")
		}

		paymentTableName := os.Getenv("PAYMENT_TABLE_NAME")
		if paymentTableName == "" {
			log.Println("No payment table found in environment")
			return errors.New("InvalidEnvironment")
		}

		userTableName := os.Getenv("USER_TABLE_NAME")
		if userTableName == "" {
			log.Println("No user table found in environment")
			return errors.New("InvalidEnvironment")
		}

		cfg, err := config.LoadDefaultConfig(ctx)

		if err != nil {
			log.Println("Configuration not set")
			return err
		}

		client := dynamodb.NewFromConfig(cfg)

		paymentKey, err := attributevalue.MarshalMap(PaymentKey{
			OrderId: paymentIntent.ID,
		})
		if err != nil {
			log.Println("Could not marshall payment key")
			return err
		}

		paymentValues := PaymentValues{}

		result, err := client.GetItem(ctx, &dynamodb.GetItemInput{
			TableName:            &paymentTableName,
			Key:                  paymentKey,
			ProjectionExpression: aws.String("userId, credits"),
		})
		if err != nil {
			log.Println("Could not retrieve item")
			return err
		}

		err = attributevalue.UnmarshalMap(result.Item, &paymentValues)
		if err != nil {
			log.Println("Failed to unmarshal payment value")
			return err
		}

		userKey, err := attributevalue.MarshalMap(UserKey{
			UserId: paymentValues.UserId,
		})
		if err != nil {
			log.Println("Could not marshall user key")
			return err
		}

		userUpdateValues, err := attributevalue.MarshalMap(UserKeyUpdate{
			Credits: paymentValues.Credits,
		})
		if err != nil {
			log.Println("Failed to marshal user update value")
			return err
		}

		completeUpdateValue, err := attributevalue.MarshalMap(CompleteUpdate{
			Complete: true,
		})
		if err != nil {
			log.Println("Failed to marshal complete update value")
			return err
		}

		_, err = client.TransactWriteItems(ctx, &dynamodb.TransactWriteItemsInput{
			TransactItems: []types.TransactWriteItem{
				{
					Update: &types.Update{
						TableName:                 &userTableName,
						Key:                       userKey,
						UpdateExpression:          aws.String("ADD credits :credits"),
						ExpressionAttributeValues: userUpdateValues,
					},
				},
				{
					Update: &types.Update{
						TableName:                 &paymentTableName,
						Key:                       paymentKey,
						UpdateExpression:          aws.String("SET complete = :complete"),
						ExpressionAttributeValues: completeUpdateValue,
					},
				},
			},
		})
		if err != nil {
			log.Println("Could not perform database updates")
			return err
		}

	default:
		log.Println("Recieved event ", event.Type)
	}

	return nil
}

func main() {
	if stripeSecretKey == "" {
		log.Fatal("Could not find stripe secret key")
	}
	if endpointSecret == "" {
		log.Fatal("Could not find endpoint secret key")
	}

	lambda.Start(HandleRequest)
}

func init() {
	stripe.Key = stripeSecretKey
}
