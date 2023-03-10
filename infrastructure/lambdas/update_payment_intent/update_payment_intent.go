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
	"github.com/aws/aws-sdk-go-v2/feature/dynamodb/expression"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	stripe "github.com/stripe/stripe-go/v74"
	"github.com/stripe/stripe-go/v74/paymentintent"
)

type Request struct {
	Credits *int    `json:"credits"`
	OrderId *string `json:"orderId"`
	UserId  *string `json:"userId"`
}

type Response struct {
	Amount int64 `json:"amount"`
}

type UpdateKey struct {
	OrderId string `dynamodbav:"orderId"`
}

type UpdateRequest struct {
	Amount  int    `dynamodbav:":amount"`
	Credits int    `dynamodbav:":credits"`
	UserId  string `dynamodbav:":userId"`
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

	if req.OrderId == nil {
		return Response{}, errors.New("PaymentIntentRequired")
	}

	if req.UserId == nil {
		return Response{}, errors.New("UsernameRequired")
	}

	paymentAmount := ComputeCreditAmount(credits)

	stripePayment := &stripe.PaymentIntentParams{
		Amount:   stripe.Int64(paymentAmount),
		Currency: stripe.String(string(stripe.CurrencyUSD)),
	}

	pi, err := paymentintent.Update(*req.OrderId, stripePayment)
	if err != nil {
		log.Println("Could not create Stripe Payment Intent")
		return Response{}, err
	}

	tableName := os.Getenv("PAYMENT_TABLE_NAME")
	if tableName == "" {
		log.Println("No payment table found in environment")
		return Response{}, errors.New("InvalidEnvironment")
	}

	cfg, err := config.LoadDefaultConfig(ctx)

	if err != nil {
		log.Println("Configuration not set")
		return Response{}, err
	}

	client := dynamodb.NewFromConfig(cfg)

	updateKey, err := attributevalue.MarshalMap(UpdateKey{
		OrderId: *req.OrderId,
	})

	if err != nil {
		log.Println("Could not marshall update keys")
		return Response{}, err
	}

	if err != nil {
		log.Println("Could not marshall update values")
		return Response{}, err
	}

	update := expression.Set(expression.Name("amount"), expression.Value(paymentAmount))
	update.Set(expression.Name("credits"), expression.Value(req.Credits))
	condition := expression.Equal(expression.Name("userId"), expression.Value(req.UserId))

	updateExpression, err := expression.NewBuilder().WithCondition(condition).WithUpdate(update).Build()

	if err != nil {
		log.Println("Could not build update expression")
		return Response{}, err
	}

	updateItemInput := dynamodb.UpdateItemInput{
		Key:                       updateKey,
		UpdateExpression:          updateExpression.Update(),
		ExpressionAttributeNames:  updateExpression.Names(),
		ExpressionAttributeValues: updateExpression.Values(),
		TableName:                 &tableName,
		ConditionExpression:       updateExpression.Condition(),
	}

	_, err = client.UpdateItem(ctx, &updateItemInput)

	if err != nil {
		log.Print("Could not save order info")
		return Response{}, err
	}

	return Response{
		Amount: pi.Amount,
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
