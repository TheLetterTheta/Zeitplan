port module Shared exposing
    ( AuthSignIn
    , AuthSignUp
    , Flags
    , Model
    , Msg(..)
    , SaveValue
    , init
    , isError
    , refreshToken
    , resendConfirmationCode
    , resendConfirmationCodeErr
    , resendConfirmationCodeOk
    , saveKey
    , signIn
    , signInErr
    , signInOk
    , signInWithGoogle
    , signInWithGoogleError
    , signInWithGoogleSuccess
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
import Browser.Events exposing (Visibility(..), onVisibilityChange)
import Decoders exposing (AuthUser, RefreshTokenPayload, authUserDecoder, refreshTokenDecoder)
import Gen.Route
import Json.Decode as Decode exposing (Decoder, nullable, string)
import Json.Decode.Pipeline exposing (required)
import Json.Encode as Encode
import Process
import Request exposing (Request)
import Task
import Time


isError : Result a b -> Bool
isError r =
    case r of
        Ok _ ->
            False

        Err _ ->
            True


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


type alias DecodedFlags =
    { logo : String, user : Maybe AuthUser, graphQlEndpoint : String }


type alias Flags =
    Decode.Value


decodeFlags : Decoder DecodedFlags
decodeFlags =
    Decode.succeed DecodedFlags
        |> required "logo" string
        |> required "currentlyLoggedInUser" (nullable authUserDecoder)
        |> required "graphQlEndpoint" string


type alias Model =
    { logo : String
    , expandHamburger : Bool
    , user : Maybe AuthUser
    , graphQlEndpoint : String
    }


scrollToElement : msg -> String -> Cmd msg
scrollToElement msg id =
    getElement id
        |> Task.andThen (\element -> setViewport element.element.x element.element.y)
        |> Task.attempt (\_ -> msg)


delayUntilTimestamp : Int -> msg -> Cmd msg
delayUntilTimestamp time msg =
    Time.now
        |> Task.map Time.posixToMillis
        |> Task.map (\now -> time - now)
        |> Task.map toFloat
        |> Task.andThen Process.sleep
        |> Task.perform (always msg)


init : Request -> Flags -> ( Model, Cmd Msg )
init _ flags =
    let
        tryDecodedFlags : Result Decode.Error DecodedFlags
        tryDecodedFlags =
            Decode.decodeValue decodeFlags flags
    in
    case tryDecodedFlags of
        Ok decodedFlags ->
            let
                maybeCommand =
                    decodedFlags.user
                        |> Maybe.map (\user -> delayUntilTimestamp (user.expiration - 60000) RequestRefreshToken)
                        |> Maybe.withDefault Cmd.none
            in
            ( Model decodedFlags.logo False decodedFlags.user decodedFlags.graphQlEndpoint, maybeCommand )

        Err _ ->
            ( Model "" False Nothing "", Cmd.none )


type Msg
    = ToggleNavbarHamburger
    | ScrollToElement String
    | NoOp
    | LogInUser AuthUser
    | SignOutOk
    | SignOutErr Encode.Value
    | RequestRefreshToken
    | RefreshToken Encode.Value
    | VisibilityChanged Visibility
    | Logout


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
            ( { model | user = Just user }
            , Cmd.batch
                [ Request.pushRoute Gen.Route.Schedule req
                , delayUntilTimestamp (user.expiration - 60000) RequestRefreshToken
                ]
            )

        SignOutOk ->
            ( { model | user = Nothing }, Request.pushRoute Gen.Route.Login req )

        RequestRefreshToken ->
            ( model, requestRefreshToken () )

        SignOutErr _ ->
            ( model, Cmd.none )

        RefreshToken token ->
            case Decode.decodeValue refreshTokenDecoder token of
                Ok tokenValue ->
                    case model.user of
                        Just user ->
                            let
                                updatedUserToken =
                                    { user | jwt = tokenValue.jwt, expiration = tokenValue.expiration }
                            in
                            ( { model | user = Just updatedUserToken }, delayUntilTimestamp (tokenValue.expiration - 60000) RequestRefreshToken )

                        Nothing ->
                            ( model, Cmd.none )

                Err _ ->
                    ( model, Cmd.none )

        VisibilityChanged v ->
            case v of
                Visible ->
                    case model.user of
                        Just user ->
                            ( model, delayUntilTimestamp (user.expiration - 60000) RequestRefreshToken )

                        Nothing ->
                            ( model, Cmd.none )

                Hidden ->
                    ( model, Cmd.none )

        Logout ->
            ( { model | user = Nothing }
            , case model.user of
                Just _ ->
                    signOut ()

                Nothing ->
                    Cmd.none
            )


subscriptions : Request -> Model -> Sub Msg
subscriptions _ _ =
    Sub.batch
        [ signOutOk (\_ -> SignOutOk)
        , signOutErr SignOutErr
        , refreshToken RefreshToken
        , onVisibilityChange VisibilityChanged
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


port signOut : () -> Cmd msg


port signOutOk : (Encode.Value -> msg) -> Sub msg


port signOutErr : (Encode.Value -> msg) -> Sub msg


port resendConfirmationCode : String -> Cmd msg


port resendConfirmationCodeOk : (Encode.Value -> msg) -> Sub msg


port resendConfirmationCodeErr : (Encode.Value -> msg) -> Sub msg


port refreshToken : (Encode.Value -> msg) -> Sub msg


port requestRefreshToken : () -> Cmd msg


port signInWithGoogle : () -> Cmd msg


port signInWithGoogleSuccess : (Encode.Value -> msg) -> Sub msg


port signInWithGoogleError : (Encode.Value -> msg) -> Sub msg
