module Pages.Pricing exposing (Model, Msg, page)

import Effect exposing (Effect)
import FontAwesome.Icon as Icon
import FontAwesome.Solid exposing (check, times)
import Gen.Params.Pricing exposing (Params)
import Html exposing (Html, br, button, div, em, h1, li, p, section, span, text, ul)
import Html.Attributes exposing (class, classList, id)
import Page
import Request
import Shared
import View exposing (View, footer, zeitplanNav)


page : Shared.Model -> Request.With Params -> Page.With Model Msg
page shared req =
    Page.advanced
        { init = init
        , update = update
        , view = view shared
        , subscriptions = subscriptions
        }



-- INIT


type alias Model =
    {}


init : ( Model, Effect Msg )
init =
    ( {}, Effect.none )



-- UPDATE


type Msg
    = SharedMsg Shared.Msg
    | NoOp


update : Msg -> Model -> ( Model, Effect Msg )
update msg model =
    case msg of
        SharedMsg sharedMsg ->
            ( model, Effect.fromShared sharedMsg )

        NoOp ->
            ( model, Effect.none )



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.none


type Color
    = Info
    | Warning
    | Success
    | Danger
    | Primary
    | Light


pricingPlan :
    { header : String
    , price : Float
    , frequency : String
    , items : List (Html msg)
    , color : Maybe Color
    , buttonText : String
    , afterText : String
    }
    -> Html msg
pricingPlan item =
    div
        [ class "pricing-plan"
        , class <|
            case item.color of
                Just Warning ->
                    "is-warning"

                Just Info ->
                    "is-info"

                Just Success ->
                    "is-success"

                Just Danger ->
                    "is-danger"

                Just Primary ->
                    "is-primary"

                Just Light ->
                    "is-primary-light"

                Nothing ->
                    ""
        ]
        [ div [ class "plan-header" ] [ text item.header ]
        , div [ class "plan-price" ]
            [ span [ class "plan-price-amount" ]
                [ span [ class "plan-price-currency" ] [ text "$" ]
                , text <| String.fromFloat item.price
                ]
            , text item.frequency
            ]
        , div [ class "plan-items" ] (item.items |> List.map (\s -> div [ class "plan-item" ] [ s ]))
        , div [ class "plan-footer" ]
            [ p [ class "wrap-text" ] [ em [] [ text item.afterText ] ]
            , button [ class "button mt-1 is-fullwidth" ] [ text item.buttonText ]
            ]
        ]


features : List String -> Html Msg
features items =
    div
        [ class "pricing-plan is-features"
        ]
        [ div [ class "plan-header" ] [ text "Features" ]
        , div [ class "plan-price" ]
            [ span [ class "plan-price-amount" ] [ text "\u{00A0}" ]
            ]
        , div [ class "plan-items" ] (items |> List.map (\s -> div [ class "plan-item" ] [ text s ]))
        , div [ class "plan-footer" ] []
        ]



-- VIEW


view : Shared.Model -> Model -> View Msg
view shared model =
    { title = "Zeitplan - Pricing"
    , body =
        [ zeitplanNav
            { logo = shared.logo
            , shared = shared
            }
            |> Html.map
                (\navMsg ->
                    case navMsg of
                        View.ToggleHamburger ->
                            SharedMsg Shared.ToggleNavbarHamburger

                        View.Logout ->
                            SharedMsg Shared.Logout
                )
        , section [ class "section" ]
            [ div [ class "container" ]
                [ h1 [ class "is-1 title" ] [ text "Costs" ]
                , div [ class "content is-medium" ]
                    [ p []
                        [ text """
                    Countless hours have gone into the devlopment of Zeitplan to make it a
                    high quality product. At least until version 1.1.0, the entire development
                    of Zeitplan has been entirely funded by the developers. We ask that you download
                    the project, or sign up for a subscription below to help support projects like
                    this, and provide a positive community for this kind of work. If you found the
                    project useful, consider sharing it with your friends!
                    """ ]
                    ]
                , h1 [ class "is-1 title" ] [ text "Early Adoption Period" ]
                , div [ class "content is-medium" ]
                    [ p []
                        [ text """
                    Currently, there are no associated costs to using Zeitplan. The following is a
                    future pricing model that will be used when Zeitplan has enough of a userbase to
                    warrant a pricing system.
                    """ ]
                    , p []
                    [ text """
                    Accounts in the future will begin with a free trial period of 1 week, followed by a
                    promotional new member discount on any of the following pricing models. In the future
                    there may also be incentives for inviting other users.
                    """]
                    ]
                , h1 [ class "is-1 title" ] [ text "Desktop Download" ]
                , div [ class "content is-medium" ]
                    [ p []
                        [ text """
                    Download and run Zeitplan unlimited on your own computer!
                    """
                        ]
                    , ul []
                        [ li []
                            [ text "Features"
                            , ul []
                                [ li [] [ text "Unlimited use" ]
                                , li [] [ text "Infinite search time" ]
                                , li [] [ text "No recurring charges" ]
                                ]
                            ]
                        , li []
                            [ text "Limitations"
                            , ul []
                                [ li [] [ text "No sync with cloud" ]
                                , li [] [ text "Limited by your computer" ]
                                , li [] [ text "Isolated from participants" ]
                                , li [] [ text "No guranteed updates" ]
                                ]
                            ]
                        ]
                    , text """
                        Downloading Zeitplan Desktop is a one time fee of $50.
                        """
                    ]
                , h1 [ class "is-1 title" ] [ text "Cloud Access" ]
                , div [ class "content is-medium" ]
                    [ p []
                        [ text """
                Zeitplan Cloud is a fully web-based application. After logging into your account,
                you will be provided with a variety of features that include
                """
                        ]
                    , ul []
                        [ li []
                            [ text "Participant upload rooms"
                            , br [] []
                            , p [ class "subtitle" ] [ text "Grants access to a custom URL for a participant to block out their own times" ]
                            ]
                        , li [] [ text "Access anywhere" ]
                        , li [] [ text "Access anytime" ]
                        , li [] [ text "Search for your perfect schedule on powerful Cloud computers" ]
                        ]
                    ]
                , div [ class "pricing-table is-comparative" ]
                    [ features
                        [ "Community Support"
                        , "Unlimited Participants"
                        , "Developer Support"
                        , "Search Time (Total)"
                        , "Meetings"
                        ]
                    , pricingPlan
                        { header = "Basic"
                        , price = 15
                        , frequency = "/ week"
                        , items =
                            [ Icon.viewIcon check
                            , Icon.viewIcon times
                            , Icon.viewIcon times
                            , text "1s (10,000)"
                            , text "20"
                            ]
                        , buttonText = "Choose"
                        , color = Nothing
                        , afterText = "Low commitment"
                        }
                    , pricingPlan
                        { header = "Advanced"
                        , price = 25
                        , frequency = "/ month"
                        , items =
                            [ Icon.viewIcon check
                            , Icon.viewIcon check
                            , Icon.viewIcon times
                            , text "5s (50,000)"
                            , text "50"
                            ]
                        , buttonText = "Choose"
                        , color = Just Light
                        , afterText = "Most popular"
                        }
                    , pricingPlan
                        { header = "Pro"
                        , price = 100
                        , frequency = "/ year"
                        , items =
                            [ Icon.viewIcon check
                            , Icon.viewIcon check
                            , text "1 hour"
                            , text "15s (150,000)"
                            , text "250"
                            ]
                        , buttonText = "Choose"
                        , color = Just Primary
                        , afterText = "Most features, Best Value"
                        }
                    ]
                ]
            ]
        , footer
        ]
    }
