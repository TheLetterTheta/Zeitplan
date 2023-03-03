module Pages.PaymentConfirmation exposing (Model, Msg, page)

import Dict
import Effect exposing (Effect, fromShared)
import Html exposing (article, div, p, section, text)
import Html.Attributes exposing (class)
import Page exposing (Page)
import Request exposing (Request)
import Shared
import View exposing (View, zeitplanNav)


page : Shared.Model -> Request -> Page.With Model Msg
page shared req =
    Page.advanced
        { init = init (Dict.get "redirect_status" req.query)
        , update = update
        , view = view shared
        , subscriptions = subscriptions
        }


type PaymentStatus
    = Success
    | Failed


type alias Model =
    { status : PaymentStatus }


init : Maybe String -> ( Model, Effect Msg )
init success =
    ( { status =
            if success == Just "succeeded" then
                Success

            else
                Failed
      }
    , Effect.none
    )


type Msg
    = SharedMsg Shared.Msg


update : Msg -> Model -> ( Model, Effect Msg )
update msg model =
    case msg of
        SharedMsg sharedMsg ->
            ( model, Effect.fromShared sharedMsg )


view : Shared.Model -> Model -> View Msg
view shared model =
    View "Zeitplan - Schedule"
        [ zeitplanNav
            { logo = shared.logo
            , shared = shared
            }
            |> Html.map SharedMsg
        , section [ class "section is-large" ]
            [ div [ class "columns is-centered" ]
                [ div [ class "column is-6" ]
                    [ case model.status of
                        Success ->
                            article [ class "message is-success" ]
                                [ div [ class "message-header" ]
                                    [ p [] [ text "Successfully processed payment!" ]
                                    ]
                                , div [ class "message-body" ]
                                    [ text """
                            Credits have been added to your account. If you do not see the increased amount, please allow at least 24 hours for payments to process, and refresh the page. If you still do not see your credits - submit an issue to the GitHub link below.
                            """ ]
                                ]

                        Failed ->
                            article [ class "message is-danger" ]
                                [ div [ class "message-header" ]
                                    [ p [] [ text "Unable to process your payment!" ]
                                    ]
                                , div [ class "message-body" ]
                                    [ text """
                            Something went wrong trying to add credits to your account! Please try again in a few hours, or submit an issue to the GitHub link below.
                            """ ]
                                ]
                    ]
                ]
            ]
        , View.footer
        ]


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.none
