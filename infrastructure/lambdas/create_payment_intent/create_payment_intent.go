package main

import (
	"context"
	"errors"
	"fmt"
	"math"
	"os"

	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/feature/dynamodb/attributevalue"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	stripe "github.com/stripe/stripe-go/v74"
	"github.com/stripe/stripe-go/v74/paymentintent"
)

type Request struct {
	UserName *string `json:"userId"`
	Credits  *int    `json:"credits"`
}

type Response struct {
	ClientSecret string `json:"clientSecret"`
	Amount       int64  `json:"amount"`
}

type InsertItem struct {
	ClientSecret string `attributevalue:"clientSecret"`
	Credits      int    `attributevalue:"credits"`
	UserId       string `json:"userId"`
	Amount       int    `attributevalue:"amount"`
}

var (
	stripeSecretKey string
)

func HandleRequest(ctx context.Context, req Request) (Response, error) {
	stripe.Key = stripeSecretKey

	if req.Credits == nil {
		return Response{}, errors.New("CreditsRequired")
	}

	if req.UserName == nil {
		return Response{}, errors.New("UsernameRequired")
	}

	credits := *req.Credits
	if credits < 5 || credits > 250 {
		return Response{}, errors.New("CreditsOutOfBounds")
	}

	tableName := os.Getenv("PAYMENT_TABLE_NAME")
	if tableName == "" {
		fmt.Println("No users table found in environment")
		return Response{}, errors.New("InvalidEnvironment")
	}

	paymentAmount := ComputeCreditAmount(credits)

	stripePayment := &stripe.PaymentIntentParams{
		Amount:      stripe.Int64(paymentAmount),
		Currency:    stripe.String(string(stripe.CurrencyUSD)),
		Description: stripe.String("Add credits to your account"),
		AutomaticPaymentMethods: &stripe.PaymentIntentAutomaticPaymentMethodsParams{
			Enabled: stripe.Bool(true),
		},
	}

	pi, err := paymentintent.New(stripePayment)
	if err != nil {
		fmt.Println("Could not create Stripe Payment Intent")
		return Response{}, err
	}

	cfg, err := config.LoadDefaultConfig(ctx)

	if err != nil {
		fmt.Println("Configuration not set")
		return Response{}, err
	}

	client := dynamodb.NewFromConfig(cfg)

	insertItem := InsertItem{
		ClientSecret: pi.ClientSecret,
		UserId:       *req.UserName,
		Credits:      *req.Credits,
		Amount:       int(paymentAmount),
	}

	result, err := attributevalue.MarshalMap(insertItem)
	if err != nil {
		fmt.Println("Failed to marshall request")
		return Response{}, err
	}

	input := &dynamodb.PutItemInput{
		Item:      result,
		TableName: aws.String(tableName),
	}

	_, err = client.PutItem(ctx, input)
	if err != nil {
		fmt.Println("Failed to write to db")
		return Response{}, err
	}

	return Response{
		ClientSecret: pi.ClientSecret,
		Amount:       pi.Amount,
	}, nil
}

// / Represents the number of cents for these credits
func ComputeCreditAmount(credits int) int64 {
	return int64(100 * (math.Round(9*math.Pow(float64(credits), 0.725)) / 4))
}

func main() {
	lambda.Start(HandleRequest)
}
