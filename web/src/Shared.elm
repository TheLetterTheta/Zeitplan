port module Shared exposing
    ( AuthError
    , AuthSignIn
    , AuthSignUp
    , Flags
    , Model
    , Msg(..)
    , SaveValue
    , init
    , resendConfirmationCode
    , resendConfirmationCodeErr
    , resendConfirmationCodeOk
    , saveKey
    , signIn
    , signInErr
    , signInOk
    , signUp
    , signUpConfirm
    , signUpConfirmErr
    , signUpConfirmOk
    , signUpErr
    , signUpOk
    , subscriptions
    , update
    )

import Browser.Dom exposing (getElement, setViewport)
import Decoders exposing (AuthUser, authUserDecoder)
import Gen.Route
import Json.Decode as Decode exposing (Decoder, bool, nullable, string)
import Json.Decode.Pipeline exposing (optional, required)
import Json.Encode as Encode
import Request exposing (Request)
import Task


type alias SaveValue =
    { key : String
    , value : Encode.Value
    }


type alias AuthSignIn =
    { username : String
    , password : String
    }


type alias AuthSignUp =
    { username : String
    , password : String
    , autoSignIn : Bool
    }


type alias CognitoUser =
    { username : String }


type AuthError
    = UserNotFound
    | PasswordIncorrect
    | Other String


type alias DecodedFlags =
    { logo : String, user : Maybe AuthUser }


type alias Flags =
    Decode.Value


decodeFlags : Decoder DecodedFlags
decodeFlags =
    Decode.succeed DecodedFlags
        |> required "logo" string
        |> required "currentlyLoggedInUser" (nullable authUserDecoder)


type alias Model =
    { logo : String
    , expandHamburger : Bool
    , user : Maybe AuthUser
    }


type Msg
    = ToggleNavbarHamburger
    | ScrollToElement String
    | NoOp
    | LogInUser AuthUser
    | SignOutOk
    | SignOutErr Encode.Value
    | Logout


scrollToElement : msg -> String -> Cmd msg
scrollToElement msg id =
    getElement id
        |> Task.andThen (\element -> setViewport element.element.x element.element.y)
        |> Task.attempt (\_ -> msg)


init : Request -> Flags -> ( Model, Cmd Msg )
init _ flags =
    let
        tryDecodedFlags : Result Decode.Error DecodedFlags
        tryDecodedFlags =
            Decode.decodeValue decodeFlags flags
    in
    case tryDecodedFlags of
        Ok decodedFlags ->
            ( Model decodedFlags.logo False decodedFlags.user, Cmd.none )

        Err _ ->
            ( Model "" False Nothing, Cmd.none )


update : Request -> Msg -> Model -> ( Model, Cmd Msg )
update req msg model =
    case msg of
        ToggleNavbarHamburger ->
            ( { model | expandHamburger = not model.expandHamburger }, Cmd.none )

        ScrollToElement scroll ->
            ( model, scrollToElement NoOp scroll )

        NoOp ->
            ( model, Cmd.none )

        LogInUser user ->
            ( { model | user = Just user }, Request.pushRoute Gen.Route.Schedule req )

        SignOutOk ->
            ( { model | user = Nothing }, Request.pushRoute Gen.Route.Login req )

        SignOutErr val ->
            ( model, Cmd.none )

        Logout ->
            ( { model | user = Nothing }
            , case model.user of
                Just user ->
                    signOut user.user.username

                Nothing ->
                    Cmd.none
            )


subscriptions : Request -> Model -> Sub Msg
subscriptions _ _ =
    Sub.batch
        [ signOutOk (\_ -> SignOutOk)
        , signOutErr SignOutErr
        ]


port saveKey : SaveValue -> Cmd msg


port signIn : AuthSignIn -> Cmd msg


port signInOk : (Encode.Value -> msg) -> Sub msg


port signInErr : (Encode.Value -> msg) -> Sub msg


port signUp : AuthSignUp -> Cmd msg


port signUpOk : (Encode.Value -> msg) -> Sub msg


port signUpErr : (Encode.Value -> msg) -> Sub msg


port signUpConfirm : { username : String, code : String } -> Cmd msg


port signUpConfirmOk : (Encode.Value -> msg) -> Sub msg


port signUpConfirmErr : (Encode.Value -> msg) -> Sub msg


port signOut : String -> Cmd msg


port signOutOk : (Encode.Value -> msg) -> Sub msg


port signOutErr : (Encode.Value -> msg) -> Sub msg


port resendConfirmationCode : String -> Cmd msg


port resendConfirmationCodeOk : (Encode.Value -> msg) -> Sub msg


port resendConfirmationCodeErr : (Encode.Value -> msg) -> Sub msg
