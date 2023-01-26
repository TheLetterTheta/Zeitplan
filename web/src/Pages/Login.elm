module Pages.Login exposing (Model, Msg, page)

import Decoders exposing (AuthUser, SignUpResult, authUserDecoder, signUpResultDecoder)
import Effect exposing (Effect)
import FontAwesome as Icon
import FontAwesome.Solid exposing (spinner)
import Gen.Params.Login exposing (Params)
import Gen.Route
import Html exposing (Html, button, div, form, h1, header, input, label, p, section, text)
import Html.Attributes exposing (class, classList, disabled, for, placeholder, style, type_, value)
import Html.Events exposing (onClick, onInput, onSubmit)
import Json.Decode as Decode exposing (Decoder, bool, string)
import Json.Decode.Pipeline exposing (required)
import Json.Encode as Encode
import Page
import Regex
import Request exposing (Request)
import Shared exposing (AuthError(..), AuthSignIn, AuthSignUp, resendConfirmationCode, resendConfirmationCodeErr, resendConfirmationCodeOk, signIn, signInErr, signInOk, signUp, signUpConfirm, signUpConfirmErr, signUpConfirmOk, signUpErr, signUpOk)
import Validate exposing (Valid, Validator, fromValid, ifBlank, ifFalse, ifInvalidEmail, ifTrue, validate)
import View exposing (View, footer, zeitplanNav)


page : Shared.Model -> Request.With Params -> Page.With Model Msg
page shared req =
    Page.advanced
        { init = init
        , update = update req
        , view = view shared
        , subscriptions = subscriptions
        }



-- INIT


isError : Result a b -> Bool
isError r =
    case r of
        Ok _ ->
            False

        Err _ ->
            True


validateUsername : Validator String String
validateUsername =
    Validate.firstError
        [ ifBlank identity "Please enter a username"
        , ifInvalidEmail identity (\_ -> "Username must be an email")
        ]


hasLowercase : String -> Bool
hasLowercase =
    Regex.contains <|
        Maybe.withDefault Regex.never <|
            Regex.fromString "[a-z]"


hasUppercase : String -> Bool
hasUppercase =
    Regex.contains <|
        Maybe.withDefault Regex.never <|
            Regex.fromString "[A-Z]"


hasDigit : String -> Bool
hasDigit =
    Regex.contains <|
        Maybe.withDefault Regex.never <|
            Regex.fromString "[0-9]"


hasSymbol : String -> Bool
hasSymbol =
    Regex.contains <|
        Maybe.withDefault Regex.never <|
            Regex.fromString "[^a-zA-Z0-9]"


validatePassword : Validator String String
validatePassword =
    Validate.firstError
        [ ifBlank identity "Please enter a password"
        , ifFalse hasLowercase "Password must contain a lowercase letter"
        , ifFalse hasUppercase "Password must contain an uppercase letter"
        , ifFalse hasDigit "Password must contain a digit 0-9"
        , ifFalse hasSymbol "Password must contain a special character"
        , ifTrue (\password -> String.length password < 12) "Password must be at least 12 characters"
        ]


validateConfirmPassword : String -> Validator String String
validateConfirmPassword compareTo =
    Validate.firstError
        [ ifBlank identity "You must retype the password"
        , ifFalse (\password -> password == compareTo) "Passwords do not match"
        ]


type AuthError
    = UserNotFound
    | PasswordIncorrect
    | UserNotConfirmedYet
    | Other String


type SignUpError
    = UserExists
    | SignUpOther String


type SignUpConfirmError
    = IncorrectCode
    | SignUpConfirmOther String


stringToAuthError : String -> Decoder AuthError
stringToAuthError error =
    Decode.succeed <|
        case error of
            "UserNotFoundException" ->
                UserNotFound

            "NotAuthorizedException" ->
                PasswordIncorrect

            "UserNotConfirmedException" ->
                UserNotConfirmedYet

            other ->
                Other other


stringToSignUpError : String -> Decoder SignUpError
stringToSignUpError error =
    Decode.succeed <|
        case error of
            "UsernameExistsException" ->
                UserExists

            other ->
                SignUpOther other


stringToSignUpConfirmError : String -> Decoder SignUpConfirmError
stringToSignUpConfirmError error =
    Decode.succeed <|
        case error of
            "CodeMismatchException" ->
                IncorrectCode

            other ->
                SignUpConfirmOther other


decodeAuthError : Decoder AuthError
decodeAuthError =
    Decode.field "code" string |> Decode.andThen stringToAuthError


decodeSignUpError : Decoder SignUpError
decodeSignUpError =
    Decode.field "code" string |> Decode.andThen stringToSignUpError


decodeSignUpConfirmError : Decoder SignUpConfirmError
decodeSignUpConfirmError =
    Decode.field "code" string |> Decode.andThen stringToSignUpConfirmError


type State
    = Login
    | SignUpStart
    | SignUpConfirm
    | ResetPassword


type alias Model =
    { state : State
    , authSignIn : AuthSignIn
    , confirmPassword : String
    , confirmationCode : String
    , validatedUsername : Maybe (Result (List String) (Validate.Valid String))
    , validatedPassword : Maybe (Result (List String) (Validate.Valid String))
    , validatedConfirmPassword : Maybe (Result (List String) (Validate.Valid String))
    , requestError : Maybe String
    , loading : Bool
    , status : Maybe String
    , signUpUser : Maybe SignUpResult
    }


init : ( Model, Effect Msg )
init =
    ( Model Login (AuthSignIn "" "") "" "" Nothing Nothing Nothing Nothing False Nothing Nothing, Effect.none )



-- UPDATE


type TextInput
    = Username
    | Password
    | ConfirmPassword
    | ConfirmationCode


type Msg
    = ChangeState State
    | LoginRequest
    | LoginOk Encode.Value
    | LoginErr Encode.Value
    | SignUpRequest
    | SignUpOk Encode.Value
    | SignUpErr Encode.Value
    | SignUpConfirmRequest
    | SignUpConfirmOk Encode.Value
    | SignUpConfirmErr Encode.Value
    | DismissRequestError
    | SharedMsg Shared.Msg
    | SetInput TextInput String
    | ResendConfirmationCode
    | ResendConfirmationCodeOk Encode.Value
    | ResendConfirmationCodeErr Encode.Value


update : Request.With Params -> Msg -> Model -> ( Model, Effect Msg )
update req msg model =
    case msg of
        ChangeState state ->
            ( { model | state = state }, Effect.none )

        LoginRequest ->
            case
                Maybe.map2
                    (Result.map2 (\username -> \password -> { username = fromValid username, password = fromValid password }))
                    model.validatedUsername
                    model.validatedPassword
            of
                Just (Ok valid) ->
                    ( model, valid |> signIn |> Effect.fromCmd )

                _ ->
                    ( model, Effect.none )

        LoginOk value ->
            case Decode.decodeValue authUserDecoder value of
                Ok user ->
                    ( { model | requestError = Nothing }, Effect.fromShared <| Shared.LogInUser user )

                Err e ->
                    ( { model | requestError = Just (Decode.errorToString e) }, Effect.none )

        LoginErr error ->
            case Decode.decodeValue decodeAuthError error of
                Ok UserNotFound ->
                    ( { model
                        | state = SignUpStart
                        , requestError = Just "Account does not exist! Please create an account to continue"
                      }
                    , Effect.none
                    )

                Ok PasswordIncorrect ->
                    ( { model | requestError = Just "Wrong password" }
                    , Effect.none
                    )

                Ok UserNotConfirmedYet ->
                    ( { model | state = SignUpConfirm }
                    , Effect.none
                    )

                Ok (Other s) ->
                    ( { model | requestError = Just s }, Effect.none )

                _ ->
                    ( { model | requestError = Just "Something went wrong!" }, Effect.none )

        SignUpRequest ->
            case
                Maybe.map2
                    (Result.map2 (\username -> \password -> { username = fromValid username, password = fromValid password, autoSignIn = True }))
                    model.validatedUsername
                    model.validatedPassword
            of
                Just (Ok valid) ->
                    if model.validatedConfirmPassword |> Maybe.map isError |> Maybe.withDefault True then
                        ( model, Effect.none )

                    else
                        ( { model | requestError = Nothing }, valid |> signUp |> Effect.fromCmd )

                _ ->
                    ( model, Effect.none )

        SignUpOk user ->
            case Decode.decodeValue signUpResultDecoder user of
                Ok signUpResult ->
                    if not signUpResult.userConfirmed then
                        ( { model | requestError = Nothing, state = SignUpConfirm, confirmPassword = "" }, Effect.none )

                    else
                        ( { model | requestError = Nothing, state = Login }
                        , Effect.none
                        )

                _ ->
                    ( { model | requestError = Just "Something unexpected went wrong!" }, Effect.none )

        SignUpErr error ->
            case Decode.decodeValue decodeSignUpError error of
                Ok UserExists ->
                    let
                        authSignIn =
                            model.authSignIn
                    in
                    ( { model
                        | requestError = Just "An account with that email already exists - try logging in instead"
                        , state = Login
                        , authSignIn = { authSignIn | password = "" }
                        , confirmPassword = ""
                        , validatedConfirmPassword = Nothing
                      }
                    , Effect.none
                    )

                Ok (SignUpOther s) ->
                    ( { model | requestError = Just s }, Effect.none )

                _ ->
                    ( { model | requestError = Just "Something went wrong!" }, Effect.none )

        SignUpConfirmRequest ->
            if String.length model.confirmationCode == 0 then
                ( model, Effect.none )

            else
                ( model
                , { username = model.authSignIn.username
                  , code = model.confirmationCode
                  }
                    |> signUpConfirm
                    |> Effect.fromCmd
                )

        SignUpConfirmOk jsVal ->
            case Decode.decodeValue authUserDecoder jsVal of
                Ok user ->
                    ( { model | requestError = Nothing }, Effect.fromShared <| Shared.LogInUser user )
                Err _ -> 
                    ( { model | requestError = Just "Could not verify user, please refresh the page" } , Effect.none )

        SignUpConfirmErr error ->
            case Decode.decodeValue decodeSignUpConfirmError error of
                Ok IncorrectCode ->
                    ( { model | requestError = Just "That code does not match" }, Effect.none )

                Ok (SignUpConfirmOther other) ->
                    ( { model | requestError = Just other }, Effect.none )

                _ ->
                    ( { model | requestError = Just "Something went wrong!" }, Effect.none )

        ResendConfirmationCode ->
            ( { model | loading = True }, Effect.fromCmd <| resendConfirmationCode model.authSignIn.username )

        ResendConfirmationCodeOk val ->
            ( { model | loading = False, status = Just "A new confirmation code has been sent" }, Effect.none )

        ResendConfirmationCodeErr err ->
            ( { model | loading = False, requestError = Just "Something went wrong!" }, Effect.none )

        DismissRequestError ->
            ( { model | requestError = Nothing }, Effect.none )

        SharedMsg sharedMsg ->
            ( model, Effect.fromShared sharedMsg )

        SetInput input value ->
            let
                authSignIn : AuthSignIn
                authSignIn =
                    model.authSignIn

                newModel : Model
                newModel =
                    case input of
                        Username ->
                            let
                                username : Result (List String) (Valid String)
                                username =
                                    validate validateUsername value
                            in
                            { model
                                | validatedUsername = Just username
                                , authSignIn = { authSignIn | username = value }
                            }

                        Password ->
                            let
                                password : Result (List String) (Valid String)
                                password =
                                    validate validatePassword value

                                confirmPassword : Result (List String) (Valid String)
                                confirmPassword =
                                    validate (validateConfirmPassword value) model.confirmPassword
                            in
                            { model
                                | validatedPassword = Just password
                                , validatedConfirmPassword = Just confirmPassword
                                , authSignIn = { authSignIn | password = value }
                            }

                        ConfirmPassword ->
                            let
                                password : Result (List String) (Valid String)
                                password =
                                    validate (validateConfirmPassword model.authSignIn.password) value
                            in
                            { model
                                | validatedConfirmPassword = Just password
                                , confirmPassword = value
                            }

                        ConfirmationCode ->
                            { model | confirmationCode = value }
            in
            ( newModel, Effect.none )



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ signInOk LoginOk
        , signInErr LoginErr
        , signUpOk SignUpOk
        , signUpErr SignUpErr
        , signUpConfirmOk SignUpConfirmOk
        , signUpConfirmErr SignUpConfirmErr
        , resendConfirmationCodeOk ResendConfirmationCodeOk
        , resendConfirmationCodeErr ResendConfirmationCodeErr
        ]



-- VIEW


pageForm : Model -> Html Msg
pageForm model =
    case model.state of
        Login ->
            form [ onSubmit LoginRequest ]
                [ div [ class "card", style "width" "600px" ]
                    [ header [ class "card-header" ]
                        [ h1 [ class "card-header-title is-size-4" ] [ text "Login" ]
                        ]
                    , div [ class "card-content" ]
                        ((case model.requestError of
                            Just message ->
                                [ div [ class "notification is-danger is-light" ]
                                    [ button [ type_ "button", class "delete", onClick DismissRequestError ] []
                                    , text message
                                    ]
                                ]

                            Nothing ->
                                []
                         )
                            ++ [ div [ class "field" ]
                                    ([ label [ class "label", for "username" ] [ text "Username" ]
                                     , div [ class "control" ]
                                        [ input
                                            [ value model.authSignIn.username
                                            , class "input"
                                            , classList
                                                [ ( "is-danger"
                                                  , Maybe.map isError model.validatedUsername |> Maybe.withDefault False
                                                  )
                                                ]
                                            , type_ "email"
                                            , placeholder "Enter your email address..."
                                            , onInput <| SetInput Username
                                            ]
                                            []
                                        ]
                                     ]
                                        ++ (case model.validatedUsername of
                                                Just (Err errors) ->
                                                    errors
                                                        |> List.head
                                                        |> Maybe.map (\error -> [ p [ class "help is-danger" ] [ text error ] ])
                                                        |> Maybe.withDefault []

                                                _ ->
                                                    []
                                           )
                                    )
                               , div [ class "field" ]
                                    ([ label [ class "label", for "password" ] [ text "Password" ]
                                     , div [ class "control" ]
                                        [ input
                                            [ value model.authSignIn.password
                                            , class "input"
                                            , classList
                                                [ ( "is-danger"
                                                  , Maybe.map isError model.validatedPassword |> Maybe.withDefault False
                                                  )
                                                ]
                                            , type_ "password"
                                            , onInput <| SetInput Password
                                            ]
                                            []
                                        ]
                                     ]
                                        ++ (case model.validatedPassword of
                                                Just (Err errors) ->
                                                    errors
                                                        |> List.head
                                                        |> Maybe.map (\error -> [ p [ class "help is-danger" ] [ text error ] ])
                                                        |> Maybe.withDefault []

                                                _ ->
                                                    []
                                           )
                                    )
                               ]
                        )
                    , div [ class "card-footer p-3 buttons" ]
                        [ button
                            [ class "button is-primary"
                            , type_ "submit"
                            , disabled <|
                                Maybe.withDefault False <|
                                    Maybe.map2 (\u -> \p -> isError u || isError p)
                                        model.validatedUsername
                                        model.validatedPassword
                            ]
                            [ text "Log In" ]
                        , button [ class "button is-text is-light", type_ "button", onClick <| ChangeState SignUpStart ] [ text "Or create an account" ]
                        ]
                    ]
                ]

        SignUpStart ->
            form [ onSubmit SignUpRequest ]
                [ div [ class "card", style "width" "600px" ]
                    [ header [ class "card-header" ]
                        [ h1 [ class "card-header-title is-size-4" ] [ text "Create an account" ]
                        ]
                    , div [ class "card-content" ]
                        ((case model.requestError of
                            Just message ->
                                [ div [ class "notification is-danger is-light" ]
                                    [ button [ type_ "button", class "delete", onClick DismissRequestError ] []
                                    , text message
                                    ]
                                ]

                            Nothing ->
                                []
                         )
                            ++ [ div [ class "field" ]
                                    ([ label [ class "label", for "username" ] [ text "Username" ]
                                     , div [ class "control" ]
                                        [ input
                                            [ value model.authSignIn.username
                                            , class "input"
                                            , classList
                                                [ ( "is-danger"
                                                  , Maybe.map isError model.validatedUsername |> Maybe.withDefault False
                                                  )
                                                ]
                                            , type_ "email"
                                            , placeholder "Enter your email address..."
                                            , onInput <| SetInput Username
                                            ]
                                            []
                                        ]
                                     ]
                                        ++ (case model.validatedUsername of
                                                Just (Err errors) ->
                                                    errors
                                                        |> List.head
                                                        |> Maybe.map (\error -> [ p [ class "help is-danger" ] [ text error ] ])
                                                        |> Maybe.withDefault []

                                                _ ->
                                                    []
                                           )
                                    )
                               , div [ class "field" ]
                                    ([ label [ class "label", for "password" ] [ text "Password" ]
                                     , div [ class "control" ]
                                        [ input
                                            [ value model.authSignIn.password
                                            , class "input"
                                            , classList
                                                [ ( "is-danger"
                                                  , Maybe.map isError model.validatedPassword |> Maybe.withDefault False
                                                  )
                                                ]
                                            , type_ "password"
                                            , onInput <| SetInput Password
                                            ]
                                            []
                                        ]
                                     ]
                                        ++ (case model.validatedPassword of
                                                Just (Err errors) ->
                                                    errors
                                                        |> List.head
                                                        |> Maybe.map (\error -> [ p [ class "help is-danger" ] [ text error ] ])
                                                        |> Maybe.withDefault []

                                                _ ->
                                                    []
                                           )
                                    )
                               , div [ class "field" ]
                                    ([ label [ class "label", for "confirmPassword" ] [ text "Confirm Password" ]
                                     , div [ class "control" ]
                                        [ input
                                            [ value model.confirmPassword
                                            , class "input"
                                            , classList
                                                [ ( "is-danger"
                                                  , Maybe.map isError model.validatedConfirmPassword |> Maybe.withDefault False
                                                  )
                                                ]
                                            , type_ "password"
                                            , onInput <| SetInput ConfirmPassword
                                            ]
                                            []
                                        ]
                                     ]
                                        ++ (case model.validatedConfirmPassword of
                                                Just (Err errors) ->
                                                    errors
                                                        |> List.head
                                                        |> Maybe.map (\error -> [ p [ class "help is-danger" ] [ text error ] ])
                                                        |> Maybe.withDefault []

                                                _ ->
                                                    []
                                           )
                                    )
                               ]
                        )
                    , div [ class "card-footer p-3 buttons" ]
                        [ button
                            [ class "button is-primary"
                            , type_ "submit"
                            , disabled <|
                                Maybe.withDefault True <|
                                    Maybe.map3 (\u -> \p -> \c -> isError u || isError p || isError c)
                                        model.validatedUsername
                                        model.validatedPassword
                                        model.validatedConfirmPassword
                            ]
                            [ text "Sign Up" ]
                        , button [ class "button is-text is-light", type_ "button", onClick <| ChangeState Login ] [ text "Already have an account? Log In" ]
                        ]
                    ]
                ]

        SignUpConfirm ->
            form [ onSubmit SignUpConfirmRequest ]
                [ div [ class "card", style "width" "600px" ]
                    [ header [ class "card-header" ]
                        [ h1 [ class "card-header-title is-size-4" ] [ text "Confirm your account" ]
                        ]
                    , div [ class "card-content" ]
                        ((case model.requestError of
                            Just message ->
                                [ div [ class "notification is-danger is-light" ]
                                    [ button [ type_ "button", class "delete", onClick DismissRequestError ] []
                                    , text message
                                    ]
                                ]

                            Nothing ->
                                []
                         )
                            ++ [ div [ class "field" ]
                                    [ label [ class "label", for "username" ] [ text "Confirmation Code" ]
                                    , div [ class "control" ]
                                        [ input
                                            [ value model.confirmationCode
                                            , class "input"
                                            , type_ "text"
                                            , placeholder "Enter the code sent to your email"
                                            , onInput <| SetInput ConfirmationCode
                                            ]
                                            []
                                        ]
                                    ]
                               ]
                        )
                    , div [ class "card-footer p-3 buttons" ]
                        [ button
                            [ class "button is-primary"
                            , type_ "submit"
                            , disabled (String.length model.confirmationCode == 0)
                            ]
                            [ text "Check Confirmation Code" ]
                        , button [ class "button is-text is-light", type_ "button", onClick <| ResendConfirmationCode ] [ text "Send new verification code" ]
                        ]
                    ]
                ]

        ResetPassword ->
            div [] []


view : Shared.Model -> Model -> View Msg
view shared model =
    { title = "Zeitplan - Login"
    , body =
        [ zeitplanNav
            { logo = shared.logo
            , shared = shared
            }
            |> Html.map SharedMsg
        , section [ class "hero is-fullheight-with-navbar" ]
            [ div [ class "hero-body", style "justify-content" "center" ]
                [ if model.loading then
                    div [ class "loading" ]
                        [ Icon.view spinner ]

                  else
                    pageForm model
                ]
            ]
        , footer
        ]
    }
