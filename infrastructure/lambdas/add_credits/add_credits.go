package main

import (
	"context"
	"errors"
	"fmt"

	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/feature/dynamodb/attributevalue"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
)

type UserAttributes struct {
	Username *string `json:"username"`
}

type Request struct {
	Attributes UserAttributes `json:"userattributes"`
}

type Event struct {
	Start int `dynamodbav:"start"`
	End   int `dynamodbav:"end"`
}

type InsertItem struct {
	UserId  string  `dynamodbav:"userId"`
	Credits int32   `dynamodbav:"credits"`
	Events  []Event `dynamodbav:"events"`
}

type Response struct {
	Message string `json:"message"`
}

func HandleRequest(ctx context.Context, req Request) error {

	if req.Attributes.Username == nil {
		return errors.New("Username not found in request")
	}

	cfg, err := config.LoadDefaultConfig(ctx)

	if err != nil {
		fmt.Println("Configuration not set")
		return err
	}

	client := dynamodb.NewFromConfig(cfg)

	insertItem := InsertItem{
		UserId:  *req.Attributes.Username,
		Credits: 20,
		Events:  make([]Event, 0),
	}

	result, err := attributevalue.MarshalMap(insertItem)
	if err != nil {
		fmt.Println("Failed to marshall request")
		return err
	}

	input := &dynamodb.PutItemInput{
		Item:      result,
		TableName: aws.String("zeitplan-user"),
	}

	_, err = client.PutItem(ctx, input)
	if err != nil {
		fmt.Println("Failed to write to db")
		return err
	}

	return nil
}

func main() {
	lambda.Start(HandleRequest)
}
