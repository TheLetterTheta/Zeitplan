port module Shared exposing
    ( Flags
    , Model
    , Msg(..)
    , SaveValue
    , init
    , saveKey
    , subscriptions
    , update
    )

import Browser.Dom exposing (getElement, setViewport)
import Json.Decode as Json
import Json.Decode.Pipeline exposing (required)
import Json.Encode as Encode
import Request exposing (Request)
import Task


type alias DecodedFlags =
    { logo : String }


type alias Flags =
    Json.Value


decodeFlags : Json.Decoder DecodedFlags
decodeFlags =
    Json.succeed DecodedFlags
        |> required "logo" Json.string


type alias Model =
    { logo : String
    , expandHamburger : Bool
    , user : Maybe {}
    }


type Msg
    = ToggleNavbarHamburger
    | ScrollToElement String
    | NoOp
    | Logout


scrollToElement : msg -> String -> Cmd msg
scrollToElement msg id =
    getElement id
        |> Task.andThen (\element -> setViewport element.element.x element.element.y)
        |> Task.attempt (\_ -> msg)


init : Request -> Flags -> ( Model, Cmd Msg )
init _ flags =
    let
        tryDecodedFlags =
            Json.decodeValue decodeFlags flags
    in
    case tryDecodedFlags of
        Ok decodedFlags ->
            ( Model decodedFlags.logo False Nothing, Cmd.none )

        Err _ ->
            ( Model "" False Nothing, Cmd.none )


update : Request -> Msg -> Model -> ( Model, Cmd Msg )
update _ msg model =
    case msg of
        ToggleNavbarHamburger ->
            ( { model | expandHamburger = not model.expandHamburger }, Cmd.none )

        ScrollToElement scroll ->
            ( model, scrollToElement NoOp scroll )

        NoOp ->
            ( model, Cmd.none )

        Logout ->
            ( { model | user = Nothing }, Cmd.none )


subscriptions : Request -> Model -> Sub Msg
subscriptions _ _ =
    Sub.none


type alias SaveValue =
    { key : String
    , value : Encode.Value
    }


port saveKey : SaveValue -> Cmd msg
