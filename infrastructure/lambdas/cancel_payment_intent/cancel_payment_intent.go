package main

import (
	"context"
	"errors"
	"log"
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
	OrderId *string `json:"orderId"`
	UserId  *string `json:"userId"`
}

type Response struct {
	Success bool `json:"success"`
}

type UpdateKey struct {
	OrderId string `dynamodbav:"orderId"`
}

type DeleteRequest struct {
	UserId string `dynamodbav:":userId"`
}

var (
	stripeSecretKey string
)

func HandleRequest(ctx context.Context, req Request) (Response, error) {
	if req.OrderId == nil {
		return Response{Success: false}, errors.New("PaymentIntentRequired")
	}

	if req.UserId == nil {
		return Response{Success: false}, errors.New("UsernameRequired")
	}

	tableName := os.Getenv("PAYMENT_TABLE_NAME")
	if tableName == "" {
		log.Println("No payment table found in environment")
		return Response{Success: false}, errors.New("InvalidEnvironment")
	}

	cfg, err := config.LoadDefaultConfig(ctx)

	if err != nil {
		log.Println("Configuration not set")
		return Response{Success: false}, err
	}

	client := dynamodb.NewFromConfig(cfg)

	deleteKey, err := attributevalue.MarshalMap(UpdateKey{
		OrderId: *req.OrderId,
	})

	if err != nil {
		log.Println("Could not marshall update keys")
		return Response{Success: false}, err
	}

	deleteCondition := expression.Equal(expression.Name("userId"), expression.Value(req.UserId))

	deleteExpression, err := expression.NewBuilder().WithCondition(deleteCondition).Build()

	if err != nil {
		log.Println("Could not build update expression")
		return Response{Success: false}, err
	}

	deleteItemInput := dynamodb.DeleteItemInput{
		Key:                       deleteKey,
		TableName:                 &tableName,
		ConditionExpression:       deleteExpression.Condition(),
		ExpressionAttributeNames:  deleteExpression.Names(),
		ExpressionAttributeValues: deleteExpression.Values(),
	}

	_, err = client.DeleteItem(ctx, &deleteItemInput)

	if err != nil {
		log.Print("Could not save order info")
		return Response{Success: false}, err
	}

	_, err = paymentintent.Cancel(*req.OrderId, nil)
	if err != nil {
		log.Println("Could not create Stripe Payment Intent")
		return Response{Success: false}, err
	}

	return Response{Success: true}, nil
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
