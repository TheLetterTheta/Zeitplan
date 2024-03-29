package main

import (
	"context"
	"errors"
	"log"
	"math"
	"os"

	"github.com/aws/aws-lambda-go/lambda"
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
	OrderId      string `json:"orderId"`
}

type NewPurchase struct {
	OrderId  string `dynamodbav:"orderId"`
	Complete bool   `dynamodbav:"complete"`
	UserId   string `dynamodbav:"userId"`
	Amount   int    `dynamodbav:"amount"`
	Credits  int    `dynamodbav:"credits"`
}

var (
	stripeSecretKey string
)

func HandleRequest(ctx context.Context, req Request) (Response, error) {
	if req.Credits == nil {
		return Response{}, errors.New("CreditsRequired")
	}

	credits := *req.Credits
	if credits < 5 || credits > 250 {
		return Response{}, errors.New("CreditsOutOfBounds")
	}

	if req.UserName == nil {
		return Response{}, errors.New("UsernameRequired")
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
		log.Println("Could not create Stripe Payment Intent")
		return Response{}, err
	}

	tableName := os.Getenv("PAYMENT_TABLE_NAME")
	if tableName == "" {
		log.Println("No payments table found in environment")
		return Response{}, errors.New("InvalidEnvironment")
	}

	cfg, err := config.LoadDefaultConfig(ctx)

	if err != nil {
		log.Println("Configuration not set")
		return Response{}, err
	}

	client := dynamodb.NewFromConfig(cfg)

	insertItem, err := attributevalue.MarshalMap(NewPurchase{
		Amount:   int(paymentAmount),
		OrderId:  pi.ID,
		Complete: false,
		Credits:  *req.Credits,
		UserId:   *req.UserName,
	})
	if err != nil {
		log.Println("Could not marshall update values")
		return Response{}, err
	}

	putItemInput := dynamodb.PutItemInput{
		Item:      insertItem,
		TableName: &tableName,
	}

	_, err = client.PutItem(ctx, &putItemInput)

	if err != nil {
		log.Print("Could not save order info")
		return Response{}, err
	}

	return Response{
		ClientSecret: pi.ClientSecret,
		Amount:       pi.Amount,
		OrderId:      pi.ID,
	}, nil
}

// / Represents the number of cents for these credits
func ComputeCreditAmount(credits int) int64 {
	return int64(100 * (math.Round(9*math.Pow(float64(credits), 0.725)) / 4))
}

func main() {
	if stripeSecretKey == "" {
		log.Fatal("Could not find stripe secret Key")
	}

	lambda.Start(HandleRequest)
}

func init() {
	stripe.Key = stripeSecretKey
}
