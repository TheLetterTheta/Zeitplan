package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/feature/dynamodb/attributevalue"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
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

type PaymentDetails struct {
	ClientSecret string `attributevalue:"clientSecret"`
	Credits      int    `attributevalue:"credits"`
	UserId       string `json:"userId"`
	Amount       int    `attributevalue:"amount"`
}
type ClientSecret struct {
	ClientSecret string `attributevalue:"clientSecret"`
}

type AddCreditsKey struct {
	UserId string `"attributevalue:"userId"`
}
type PurchasedCredits struct {
	PurchasedCredits int `attributevalue:":purchasedCredits"`
}

func HandleRequest(ctx context.Context, req events.LambdaFunctionURLRequest) error {
	stripe.Key = stripeSecretKey

	event, err := webhook.ConstructEvent([]byte(req.Body), req.Headers["Stripe-Signature"], endpointSecret)

	if err != nil {
		fmt.Println("Could not verify request")
		return errors.New("InvalidRequest")
	}

	switch event.Type {
	case "payment_intent.succeeded":
		var paymentIntent stripe.PaymentIntent
		err := json.Unmarshal(event.Data.Raw, &paymentIntent)

		if err != nil {
			fmt.Println("Could not parse Payment Intent")
			return err
		}

		// TODO: Update customer with credits
		// GET User by payment intent from Dynamodb

		tableName := os.Getenv("PAYMENT_TABLE_NAME")
		if tableName == "" {
			fmt.Println("No users table found in environment")
			return errors.New("InvalidEnvironment")
		}

		cfg, err := config.LoadDefaultConfig(ctx)

		if err != nil {
			fmt.Println("Configuration not set")
			return err
		}

		client := dynamodb.NewFromConfig(cfg)

		clientSecret, err := attributevalue.MarshalMap(ClientSecret{
			ClientSecret: paymentIntent.ClientSecret,
		})
		if err != nil {
			fmt.Println("Could not marshal Client Secret")
			return err
		}

		getItemInput := &dynamodb.GetItemInput{
			TableName: aws.String(tableName),
			Key:       clientSecret,
		}

		result, err := client.GetItem(ctx, getItemInput)
		if err != nil {
			fmt.Println("Could not generate query")
			return err
		}

		if result.Item == nil {
			fmt.Println("Could not find existing payment intent")
			return errors.New("MissingPaymentIntent")
		}

		paymentDetails := PaymentDetails{}

		err = attributevalue.UnmarshalMap(result.Item, &paymentDetails)
		if err != nil {
			fmt.Println("Could not unmarshal db value")
			return err
		}

		key, err := attributevalue.MarshalMap(AddCreditsKey{
			UserId: paymentDetails.UserId,
		})

		if err != nil {
			fmt.Println("Could not marshall Key")
			return err
		}

		credits, err := attributevalue.MarshalMap(PurchasedCredits{
			PurchasedCredits: paymentDetails.Credits,
		})

		if err != nil {
			fmt.Println("Could not marshall credits")
			return err
		}

		addCreditsInput := &dynamodb.UpdateItemInput{
			Key:                       key,
			UpdateExpression:          aws.String("SET credits = credits + :purchasedCredits"),
			ExpressionAttributeValues: credits,
		}

		_, err = client.UpdateItem(ctx, addCreditsInput)
		if err != nil {
			fmt.Println("CreditsNotAdded")
			return err
		}

		break

	default:
		fmt.Println("Recieved event %s", event.Type)
	}

	return nil
}

func main() {
	if stripeSecretKey == "" {
		os.Exit(1)
	}
	if endpointSecret == "" {
		os.Exit(1)
	}
	fmt.Println(stripeSecretKey)
	fmt.Println(endpointSecret)

	lambda.Start(HandleRequest)
}
