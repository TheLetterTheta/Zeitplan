module Pages.Login exposing (Model, Msg, State, page)

import Browser.Navigation
import Decoders exposing (AuthUser, SignUpResult, authUserDecoder, signUpResultDecoder)
import Effect exposing (Effect)
import FontAwesome as Icon
import FontAwesome.Attributes exposing (fa4x, spin)
import FontAwesome.Brands as Brands
import FontAwesome.Solid as Solid exposing (spinner)
import Gen.Params.Login exposing (Params)
import Gen.Route
import Html exposing (Html, button, div, form, h1, h2, header, hr, input, label, p, section, span, text)
import Html.Attributes exposing (class, classList, disabled, for, id, placeholder, style, type_, value)
import Html.Events exposing (onClick, onInput, onSubmit)
import Json.Decode as Decode exposing (Decoder, string)
import Json.Encode as Encode
import Page
import Process
import Regex
import Request
import Shared exposing (AuthSignIn, forgotPassword, forgotPasswordErr, forgotPasswordOk, forgotPasswordSubmit, forgotPasswordSubmitErr, forgotPasswordSubmitOk, isError, resendConfirmationCode, resendConfirmationCodeErr, resendConfirmationCodeOk, signIn, signInErr, signInOk, signInWithGoogle, signInWithGoogleError, signInWithGoogleSuccess, signUp, signUpConfirm, signUpConfirmErr, signUpConfirmOk, signUpErr, signUpOk)
import Task
import Validate exposing (Valid, Validator, fromValid, ifBlank, ifFalse, ifInvalidEmail, ifTrue, validate)
import View exposing (View, footer, zeitplanNav)


page : Shared.Model -> Request.With Params -> Page.With Model Msg
page shared req =
    Page.advanced
        { init = init shared.user req
        , update = update req
        , view = view shared
        , subscriptions = subscriptions
        }



-- INIT


validateUsername : Validator String String
validateUsername =
    Validate.firstError
        [ ifBlank identity "Please enter a username"
        , ifInvalidEmail identity (\_ -> "Email must be an email")
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
    | InvalidParameter
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

            "InvalidParameterException" ->
                InvalidParameter

            other ->
                SignUpConfirmOther other


type ForgotPasswordError
    = ForgotUserNotFound
    | LimitExceeded
    | ForgotPasswordOther String


stringToForgotPasswordError : String -> Decoder ForgotPasswordError
stringToForgotPasswordError error =
    Decode.succeed <|
        case error of
            "UserNotFoundException" ->
                ForgotUserNotFound

            "LimitExceededException" ->
                LimitExceeded

            other ->
                ForgotPasswordOther other


type ForgotPasswordSubmitError
    = ForgotIncorrectCode
    | ForgotOther String


stringToForgotPasswordSubmitError : String -> Decoder ForgotPasswordSubmitError
stringToForgotPasswordSubmitError error =
    Decode.succeed <|
        case error of
            "CodeMismatchException" ->
                ForgotIncorrectCode

            other ->
                ForgotOther other


decodeAuthError : Decoder AuthError
decodeAuthError =
    Decode.field "code" string |> Decode.andThen stringToAuthError


decodeSignUpError : Decoder SignUpError
decodeSignUpError =
    Decode.field "code" string |> Decode.andThen stringToSignUpError


decodeSignUpConfirmError : Decoder SignUpConfirmError
decodeSignUpConfirmError =
    Decode.field "code" string |> Decode.andThen stringToSignUpConfirmError


decodeForgotPasswordError : Decoder ForgotPasswordError
decodeForgotPasswordError =
    Decode.field "code" string |> Decode.andThen stringToForgotPasswordError


decodeForgotPasswordSubmitError : Decoder ForgotPasswordSubmitError
decodeForgotPasswordSubmitError =
    Decode.field "code" string |> Decode.andThen stringToForgotPasswordSubmitError


type State
    = Login
    | SignUpStart
    | SignUpConfirm
    | Redirecting
    | ForgotPassword
    | ForgotPasswordCodeSubmit


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


init : Maybe AuthUser -> Request.With Params -> ( Model, Effect Msg )
init user req =
    ( Model Login (AuthSignIn "" "") "" "" Nothing Nothing Nothing Nothing False Nothing Nothing
    , if user == Nothing then
        Effect.none

      else
        Effect.fromCmd <| Request.pushRoute Gen.Route.Schedule req
    )



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
    | DismissStatus
    | SharedMsg Shared.Msg
    | SetInput TextInput String
    | LoginWithGoogle
    | LoginWithGoogleSuccess Encode.Value
    | LoginWithGoogleError Encode.Value
    | ResendConfirmationCode
    | ResendConfirmationCodeOk Encode.Value
    | ResendConfirmationCodeErr Encode.Value
    | SendForgotPassword
    | ForgotPasswordOk Encode.Value
    | ForgotPasswordErr Encode.Value
    | SendForgotPasswordCode
    | ForgotPasswordCodeOk Encode.Value
    | ForgotPasswordCodeErr Encode.Value


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

        LoginWithGoogle ->
            ( { model | loading = True }, Effect.fromCmd <| signInWithGoogle () )

        LoginWithGoogleSuccess _ ->
            ( { model | loading = False, state = Redirecting }, Effect.none )

        LoginWithGoogleError error ->
            ( { model | loading = False, state = Login, requestError = Just "Could not login with Google!" }, Effect.none )

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
                    ( { model | requestError = Just "Could not verify user, please refresh the page" }, Effect.none )

        SignUpConfirmErr error ->
            case Decode.decodeValue decodeSignUpConfirmError error of
                Ok IncorrectCode ->
                    ( { model | requestError = Just "That code does not match" }, Effect.none )

                Ok (SignUpConfirmOther other) ->
                    ( { model | requestError = Just other }, Effect.none )

                Ok InvalidParameter ->
                    ( { model | requestError = Just "That is not a valid code" }, Effect.none )

                _ ->
                    ( { model | requestError = Just "Something went wrong! Please refresh the page, and login again." }
                    , Effect.none
                    )

        ResendConfirmationCode ->
            ( { model | loading = True }, Effect.fromCmd <| resendConfirmationCode model.authSignIn.username )

        ResendConfirmationCodeOk _ ->
            ( { model | loading = False, status = Just "A new confirmation code has been sent" }, Effect.none )

        ResendConfirmationCodeErr _ ->
            ( { model | loading = False, requestError = Just "Something went wrong!" }, Effect.none )

        SendForgotPassword ->
            ( { model | loading = True }, Effect.fromCmd <| forgotPassword model.authSignIn.username )

        ForgotPasswordOk _ ->
            ( { model | state = ForgotPasswordCodeSubmit, loading = False, status = Just "A code has been emailed to your account" }, Effect.none )

        ForgotPasswordErr error ->
            case Decode.decodeValue decodeForgotPasswordError error of
                Ok ForgotUserNotFound ->
                    ( { model | requestError = Just "That account does not exist, try creating an account instead", state = SignUpStart, loading = False }, Effect.none )

                Ok LimitExceeded ->
                    ( { model | requestError = Just "There have been too many attempts to reset that account password", loading = False }, Effect.none )

                Ok (ForgotPasswordOther _) ->
                    ( { model | requestError = Just "That account can't be recovered. Please file an issue if you believe there to be an error", loading = False }, Effect.none )

                _ ->
                    ( { model | loading = False, requestError = Just "Something went wrong - please refresh and try again." }, Effect.none )

        SendForgotPasswordCode ->
            case
                Maybe.map2
                    (Result.map2 (\username -> \password -> { username = fromValid username, password = fromValid password }))
                    model.validatedUsername
                    model.validatedPassword
            of
                Just (Ok valid) ->
                    ( { model | loading = True }, Effect.fromCmd <| forgotPasswordSubmit { username = valid.username, password = valid.password, code = model.confirmationCode } )

                _ ->
                    ( model, Effect.none )

        ForgotPasswordCodeOk _ ->
            ( { model | loading = False, state = Login, status = Just "Your password has been reset - please login with your new credentials" }, Effect.none )

        ForgotPasswordCodeErr error ->
            case Decode.decodeValue decodeForgotPasswordSubmitError error of
                Ok ForgotIncorrectCode ->
                    ( { model | loading = False, requestError = Just "The code does not match" }, Effect.none )

                Ok (ForgotOther _) ->
                    ( { model | loading = False, requestError = Just "Your password could not be reset - please verify the information below again" }, Effect.none )

                _ ->
                    ( { model | loading = False, requestError = Just "Something went wrong" }, Effect.none )

        DismissRequestError ->
            ( { model | requestError = Nothing }, Effect.none )

        DismissStatus ->
            ( { model | status = Nothing }, Effect.none )

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
        , signInWithGoogleSuccess LoginWithGoogleSuccess
        , signInWithGoogleError LoginWithGoogleError
        , signUpConfirmErr SignUpConfirmErr
        , resendConfirmationCodeOk ResendConfirmationCodeOk
        , resendConfirmationCodeErr ResendConfirmationCodeErr
        , forgotPasswordOk ForgotPasswordOk
        , forgotPasswordErr ForgotPasswordErr
        , forgotPasswordSubmitOk ForgotPasswordCodeOk
        , forgotPasswordSubmitErr ForgotPasswordCodeErr
        ]



-- VIEW


viewRequestError : Model -> Html Msg
viewRequestError model =
    case model.requestError of
        Just message ->
            div [ class "notification is-danger is-light" ]
                [ button [ type_ "button", class "delete", onClick DismissRequestError ] []
                , text message
                ]

        Nothing ->
            text ""


viewStatus : Model -> Html Msg
viewStatus model =
    case model.status of
        Nothing ->
            text ""

        Just message ->
            div [ class "notification is-success is-light" ]
                [ button [ type_ "button", class "delete", onClick DismissStatus ] []
                , text message
                ]


pageForm : Model -> Html Msg
pageForm model =
    case model.state of
        Redirecting ->
            div [ class "card" ]
                [ div [ class "card-header" ]
                    [ h2 [ class "card-header-title" ] [ text "Please login to Google" ]
                    ]
                , div
                    [ class "card-content" ]
                    [ p [] [ text "Please wait while we attempt to contact Google" ]
                    ]
                ]

        Login ->
            form [ onSubmit LoginRequest ]
                [ button [ class "button is-primary is-fullwidth is-large", type_ "button", onClick <| LoginWithGoogle ]
                    [ span [ class "icon" ] [ Icon.view Brands.google ]
                    , span [] [ text "Login with Google" ]
                    ]
                , div [ class "divider py-3" ] [ text "Or" ]
                , div [ class "card", style "width" "600px" ]
                    [ header [ class "card-header" ]
                        [ h2 [ class "card-header-title is-size-4" ] [ text "Login" ]
                        , button
                            [ class "card-header-icon", type_ "button", onClick <| ChangeState SignUpStart ]
                            [ span [ class "mr-1" ] [ Icon.view Solid.userPlus ]
                            , span [] [ text "Sign Up" ]
                            ]
                        ]
                    , div [ class "card-content" ]
                        (viewRequestError model
                            :: viewStatus model
                            :: [ div [ class "field" ]
                                    [ label [ class "label", for "email" ] [ text "Email" ]
                                    , div [ class "control" ]
                                        [ input
                                            [ value model.authSignIn.username
                                            , id "email"
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
                               , div [ class "field" ]
                                    [ label [ class "label", for "password" ] [ text "Password" ]
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
                                            , id "password"
                                            , onInput <| SetInput Password
                                            ]
                                            []
                                        ]
                                    ]
                               ]
                        )
                    , div [ class "card-footer p-3 buttons" ]
                        [ div [ class "is-flex is-flex-grow-1 is-justify-content-space-between" ]
                            [ div []
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
                                ]
                            , button [ class "button is-text is-light", type_ "button", onClick <| ChangeState ForgotPassword ] [ text "Forgot Password?" ]
                            ]
                        ]
                    ]
                ]

        SignUpStart ->
            form [ onSubmit SignUpRequest ]
                [ button [ class "button is-primary is-fullwidth is-large", type_ "button", onClick <| LoginWithGoogle ]
                    [ span [ class "icon" ] [ Icon.view Brands.google ]
                    , span [] [ text "Login with Google" ]
                    ]
                , div [ class "divider py-3" ] [ text "Or" ]
                , div [ class "card", style "width" "600px" ]
                    [ header [ class "card-header" ]
                        [ h1 [ class "card-header-title is-size-4" ] [ text "Create an account" ]
                        ]
                    , div [ class "card-content" ]
                        (viewRequestError model
                            :: viewStatus model
                            :: [ div [ class "field" ]
                                    ([ label [ class "label", for "email" ] [ text "Email" ]
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
                                            , id "email"
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
                                            , id "password"
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
                                    ([ label [ class "label", for "confirm-password" ] [ text "Confirm Password" ]
                                     , div [ class "control" ]
                                        [ input
                                            [ value model.confirmPassword
                                            , class "input"
                                            , id "confirm-password"
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
                    , div [ class "card-footer p-3 buttons is-justify-content-space-between" ]
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
                        (viewRequestError model
                            :: viewStatus model
                            :: [ div [ class "field" ]
                                    [ label [ class "label", for "code" ] [ text "Confirmation Code" ]
                                    , div [ class "control" ]
                                        [ input
                                            [ value model.confirmationCode
                                            , class "input"
                                            , id "code"
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

        ForgotPassword ->
            form [ onSubmit SendForgotPassword ]
                [ div [ class "card", style "width" "600px" ]
                    [ header [ class "card-header" ]
                        [ h1 [ class "card-header-title is-size-4" ] [ text "Forgot Password" ] ]
                    , div [ class "card-content" ]
                        (viewRequestError model
                            :: viewStatus model
                            :: [ div [ class "field" ]
                                    [ label [ class "label", for "email" ] [ text "Email" ]
                                    , div [ class "control" ]
                                        [ input
                                            [ value model.authSignIn.username
                                            , class "input"
                                            , id "email"
                                            , type_ "email"
                                            , placeholder "Enter your account email address"
                                            , onInput <| SetInput Username
                                            ]
                                            []
                                        ]
                                    ]
                               ]
                        )
                    , div [ class "card-footer is-justify-content-space-between p-3 buttons" ]
                        [ button
                            [ class "button is-primary"
                            , type_ "submit"
                            , disabled <|
                                Maybe.withDefault True <|
                                    Maybe.map isError model.validatedUsername
                            ]
                            [ text "Send reset code" ]
                        , button [ class "button is-text is-light", type_ "button", onClick <| ChangeState Login ] [ text "Back to Login" ]
                        ]
                    ]
                ]

        ForgotPasswordCodeSubmit ->
            form [ onSubmit SendForgotPasswordCode ]
                [ div [ class "card", style "width" "600px" ]
                    [ header [ class "card-header" ]
                        [ h1 [ class "card-header-title is-size-4" ] [ text "Forgot Password Reset" ] ]
                    , div [ class "card-content" ]
                        (viewRequestError model
                            :: viewStatus model
                            :: [ div [ class "field" ]
                                    [ label [ class "label", for "email" ] [ text "Email" ]
                                    , div [ class "control" ]
                                        [ input
                                            [ value model.authSignIn.username
                                            , class "input"
                                            , id "email"
                                            , type_ "email"
                                            , placeholder "Enter your account email address"
                                            , disabled True
                                            ]
                                            []
                                        ]
                                    ]
                               , div [ class "field" ]
                                    [ label [ class "label", for "code" ] [ text "Verification Code" ]
                                    , div [ class "control" ]
                                        [ input
                                            [ value model.confirmationCode
                                            , class "input"
                                            , id "code"
                                            , type_ "text"
                                            , placeholder "Enter the verification code sent to your email"
                                            , onInput <| SetInput ConfirmationCode
                                            ]
                                            []
                                        ]
                                    ]
                               , div [ class "field" ]
                                    [ label [ class "label", for "password" ] [ text "New Password" ]
                                    , div [ class "control" ]
                                        ([ input
                                            [ value model.authSignIn.password
                                            , class "input"
                                            , id "password"
                                            , type_ "password"
                                            , classList
                                                [ ( "is-danger"
                                                  , Maybe.map isError model.validatedPassword |> Maybe.withDefault False
                                                  )
                                                ]
                                            , placeholder "Enter your new password"
                                            , onInput <| SetInput Password
                                            ]
                                            []
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
                               , div [ class "field" ]
                                    [ label [ class "label", for "confirm-password" ] [ text "Confirm New Password" ]
                                    , div [ class "control" ]
                                        ([ input
                                            [ value model.confirmPassword
                                            , class "input"
                                            , id "confirm-password"
                                            , classList
                                                [ ( "is-danger"
                                                  , Maybe.map isError model.validatedConfirmPassword |> Maybe.withDefault False
                                                  )
                                                ]
                                            , type_ "password"
                                            , placeholder "Re-enter your password"
                                            , onInput <| SetInput ConfirmPassword
                                            ]
                                            []
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
                               ]
                        )
                    , div [ class "card-footer is-justify-content-space-between p-3 buttons" ]
                        [ button
                            [ class "button is-primary"
                            , disabled <|
                                Maybe.withDefault True <|
                                    Maybe.map3 (\u -> \p -> \c -> isError u || isError p || isError c || String.length model.confirmationCode < 1)
                                        model.validatedUsername
                                        model.validatedPassword
                                        model.validatedConfirmPassword
                            , type_ "submit"
                            ]
                            [ text "Reset Password" ]
                        , button [ class "button is-text is-light", type_ "button", onClick <| ChangeState Login ] [ text "Back to Login" ]
                        ]
                    ]
                ]


view : Shared.Model -> Model -> View Msg
view shared model =
    { title = "Zeitplan - Login"
    , body =
        [ zeitplanNav
            { logo = shared.logo
            , shared = shared
            }
            |> Html.map SharedMsg
        , section [ class "section is-large" ]
            [ div [ class "columns is-centered" ]
                [ div [ class "column is-narrow" ]
                    (if model.loading then
                        [ div [ style "display" "grid", style "place-items" "center" ]
                            [ span
                                [ style "grid-column" "1"
                                , style "grid-row" "1"
                                , style "z-index" "2"
                                ]
                                [ Icon.view <| Icon.styled [ spin, fa4x ] spinner ]
                            , div
                                [ style "grid-column" "1"
                                , style "grid-row" "1"
                                , class "loading ignore-pointer-events is-clipped"
                                ]
                                [ pageForm model ]
                            ]
                        ]

                     else
                        [ pageForm model ]
                    )
                ]
            ]
        , footer
        ]
    }
