module Pages.Home_ exposing (Model, Msg, page)

import Effect exposing (Effect)
import Gen.Params.Home_ exposing (Params)
import Html exposing (div, h1, h2, h5, p, section, strong, text)
import Html.Attributes exposing (class)
import Page
import Request
import Shared
import View exposing (View, container, content, footer, zeitplanNav)


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


update : Msg -> Model -> ( Model, Effect Msg )
update msg model =
    case msg of
        SharedMsg sharedMsg ->
            ( model, Effect.fromShared sharedMsg )



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.none



-- VIEW


view : Shared.Model -> Model -> View Msg
view shared _ =
    { title = "Zeitplan - Home"
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
        , section [ class "hero is-fullheight-with-navbar is-dark" ]
            [ div [ class "hero-head" ]
                [ div [ class "section" ]
                    [ p [ class "title" ] [ text "Zeitplan" ]
                    , p [ class "subtitle" ] [ text "A different kind of scheduler" ]
                    ]
                ]
            , div [ class "hero-body" ]
                [ div [ class "level" ]
                    [ div [ class "level-item" ]
                        [ div [class "has-text-centered"]
                            [ p [ class "heading" ] [ text "Version" ]
                            , p [ class "title" ] [ text "1.1.0" ]
                            ]
                        ]
                    ]
                ]
            , div [ class "hero-foot" ]
                []
            ]
        , div [ class "section is-large" ]
            []
        , footer
        ]
    }
