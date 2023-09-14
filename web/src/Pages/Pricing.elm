module Pages.Pricing exposing (Model, Msg, page)

import Effect exposing (Effect)
import FontAwesome as Icon
import FontAwesome.Solid exposing (check, times)
import Gen.Params.Pricing exposing (Params)
import Html exposing (Html, br, button, div, em, h1, h2, li, p, section, span, text, ul)
import Html.Attributes exposing (class)
import Page
import Request
import Shared
import View exposing (View, footer, zeitplanNav)


page : Shared.Model -> Request.With Params -> Page.With Model Msg
page shared _ =
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


update : Msg -> Model -> ( Model, Effect Msg )
update msg model =
    case msg of
        SharedMsg sharedMsg ->
            ( model, Effect.fromShared sharedMsg )



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.none


type Color
    = Primary
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
view shared _ =
    { title = "Zeitplan - Pricing"
    , body =
        [ zeitplanNav
            { logo = shared.logo
            , shared = shared
            }
            |> Html.map SharedMsg
        , div [ class "is-small section" ]
            [ div [ class "container" ]
                [ div [ class "hero is-dark" ]
                    [ div [ class "hero-body" ]
                        [ h1 [ class "is-1 title" ] [ text "Pricing" ]
                        , h2 [ class "subtitle" ] [ text "Because nothing in life is free" ]
                        ]
                    ]
                ]
            ]
        , section [ class "section" ]
            [ div [ class "container" ]
                [ h2 [ class "is-1 title" ] [ text "Costs" ]
                , div [ class "content is-medium" ]
                    [ p []
                        [ text """
                    Countless hours have gone into the devlopment of Zeitplan to make it a
                    high quality product. At least until version 1.1.0, the entire development
                    of Zeitplan has been entirely funded by a single developer. We ask that you download
                    the project, or sign up for an account and purchase credits to help support projects like
                    this, and provide a positive community for this kind of work. If you found the
                    project useful, consider sharing it with your friends!
                    """ ]
                    ]
                , h2 [ class "is-1 title" ] [ text "Early Adoption Period" ]
                , div [ class "content is-medium" ]
                    [ p []
                        [ text """
                    Currently, there are no associated costs to using Zeitplan. Each user when signing up
                    will receive 10 credits to use to schedule their meetings with. Scheduling meetings may
                    cost multiple credits based on the complexity of the schedule. This is due to the fact
                    that these computations are expensive to run.
                    """ ]
                    ]
                , h2 [ class "is-1 title" ] [ text "Cloud Access" ]
                , div [ class "content is-medium" ]
                    [ p []
                        [ text """
                        Zeitplan can also be run from this website. Simply Sign Up for an account,
                        and schedule meetings to your hearts content!
                    """
                        ]
                    , ul []
                        [ li [] [ text "Access anywhere" ]
                        , li [] [ text "Access anytime" ]
                        , li [] [ text "Search for your perfect schedule on powerful Cloud computers" ]
                        ]
                    ]
                , h2 [ class "is-1 title" ] [ text "Desktop Download" ]
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
                ]
            ]
        , footer
        ]
    }
