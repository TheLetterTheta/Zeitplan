module Shared exposing
    ( Flags
    , Model
    , Msg(..)
    , init
    , subscriptions
    , update
    )

import Json.Decode as Json
import Json.Decode.Pipeline exposing (required)
import Request exposing (Request)


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
    | Logout


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

        Logout ->
            ( { model | user = Nothing }, Cmd.none )


subscriptions : Request -> Model -> Sub Msg
subscriptions _ _ =
    Sub.none
