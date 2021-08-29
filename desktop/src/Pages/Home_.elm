module Pages.Home_ exposing (Model, Msg, page)

import Effect exposing (Effect)
import Gen.Params.Home_ exposing (Params)
import Html exposing (div, h1, h2, h5, p, strong, text)
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
            , toggleHamburger = SharedMsg Shared.ToggleNavbarHamburger
            , logout = SharedMsg Shared.Logout
            }
        , container []
            []
        , footer
        ]
    }
