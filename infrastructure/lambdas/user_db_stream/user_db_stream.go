package main

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	v4 "github.com/aws/aws-sdk-go-v2/aws/signer/v4"
	awshttp "github.com/aws/aws-sdk-go-v2/aws/transport/http"
	"github.com/aws/aws-sdk-go-v2/config"
)

type UserKey struct {
	UserId string `dynamodbav:"userId"`
}

type NewCredits struct {
	Credits int `dynamodbav:"credits"`
}

type GraphQlQuery struct {
	Query         string `json:"query"`
	OperationName string `json:"operationName"`
	Variables     *int   `json:"variables"`
}

var (
	apiUrl              string
	cognitoClientId     string
	cognitoClientSecret string
)

func init() {
	apiUrl = os.Getenv("GQL_URL")
	if apiUrl == "" {
		log.Println("Could not read Graph QL API Url")
	}

}

func HandleRequest(ctx context.Context, req events.DynamoDBEvent) error {
	cfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		log.Println("Configuration not set")
		return err
	}

	mutation := "mutation P {"
	name := 'a'
	for _, record := range req.Records {
		switch record.EventName {
		case "MODIFY":
			userIdDB := record.Change.Keys["userId"]
			creditsDB := record.Change.NewImage["credits"]

			userId := userIdDB.String()
			if userId == "" {
				log.Println("Could not read credits")
				return errors.New("DBEventError")
			}

			credits, err := creditsDB.Integer()
			if err != nil {
				log.Println("Could not read credits")
				return err
			}
			mutation += fmt.Sprintf(`\n %c: creditsChanged(userId:"%s", credits:%d)`, name, userId, credits)
			name += 1
		default:
			log.Print("Got event:", record.EventName)
		}
	}

	mutation += `\n }`

	jsonBody, err := json.Marshal(GraphQlQuery{
		Query:         mutation,
		OperationName: "P",
		Variables:     nil,
	})

	log.Println("Request Body", string(jsonBody))

	if err != nil {
		log.Println("Could not create request body")
		return err
	}

	client := awshttp.NewBuildableClient()
	if err != nil {
		log.Println("Could not create HTTP client")
		return err
	}

	hashValue := sha256.Sum256(jsonBody)
	hexHash := hex.EncodeToString(hashValue[:])
	v4.SetPayloadHash(ctx, hexHash)

	log.Println("Payload Hash:", hexHash)

	request, err := http.NewRequestWithContext(ctx, http.MethodPost, apiUrl, bytes.NewBuffer(jsonBody))
	if err != nil {
		log.Println("Could not make request")
		return err
	}

	request.Header.Add("accept", "application/json, text/javascript")
	request.Header.Add("content-encoding", "amz-1.0")
	request.Header.Add("content-type", "application/json;charset=UTF-8")

	signer := v4.NewSigner(func(signer *v4.SignerOptions) {
		signer.LogSigning = true
	})

	credentials, err := cfg.Credentials.Retrieve(ctx)
	if err != nil {
		log.Println("Could not retrieve credentials")
		return err
	}

	err = signer.SignHTTP(ctx, credentials, request, hexHash, "appsync", cfg.Region, time.Now())
	if err != nil {
		log.Println("Could not sign HTTP Request")
		return err
	}

	if resp, err := client.Do(request); err != nil || resp.StatusCode >= 400 {

		log.Println("Request:", request.Header, request.Body)

		if resp == nil {
			log.Println("Could not send request - no response")
			return err
		}

		if resp.Body != nil {
			respBody, _ := io.ReadAll(resp.Body)
			log.Println("Could not send request", resp.Status, string(respBody))
		} else {
			log.Println("Could not send request", resp.Status)
		}
		return err
	}

	return nil

}

func main() {
	lambda.Start(HandleRequest)
}
