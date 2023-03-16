package main

import (
	"context"
	"errors"
	"fmt"
	"os"
	"strconv"

	"github.com/aws/aws-lambda-go/events"
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
	Credits int     `dynamodbav:"credits"`
	Events  []Event `dynamodbav:"events"`
}

type Response struct {
	Message string `json:"message"`
}

func HandleRequest(ctx context.Context, req events.CognitoEventUserPoolsPostConfirmation) (events.CognitoEventUserPoolsPostConfirmation, error) {

	if req.UserName == "" {
		return req, errors.New("UsernameNotFound")
	}

	credits, err := strconv.Atoi(os.Getenv("DEFAULT_CREDITS"))
	if err != nil {
		fmt.Println("Invalid default credits amount")
		return req, err
	}

	tableName := os.Getenv("USER_TABLE_NAME")
	if tableName == "" {
		fmt.Println("No users table found in environment")
		return req, errors.New("InvalidEnvironment")
	}

	cfg, err := config.LoadDefaultConfig(ctx)

	if err != nil {
		fmt.Println("Configuration not set")
		return req, err
	}

	client := dynamodb.NewFromConfig(cfg)

	insertItem := InsertItem{
		UserId:  req.UserName,
		Credits: credits,
		Events:  make([]Event, 0),
	}

	result, err := attributevalue.MarshalMap(insertItem)
	if err != nil {
		fmt.Println("Failed to marshall request")
		return req, err
	}

	input := &dynamodb.PutItemInput{
		Item:      result,
		TableName: aws.String(tableName),
	}

	_, err = client.PutItem(ctx, input)
	if err != nil {
		fmt.Println("Failed to write to db")
		return req, err
	}

	return req, nil
}

func main() {
	lambda.Start(HandleRequest)
}
