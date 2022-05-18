module Pages.SignUp exposing (Model, Msg, page)

import Effect exposing (Effect)
import Gen.Params.SignUp exposing (Params)
import Page
import Request
import Shared
import View exposing (View)
import Page


page : Shared.Model -> Request.With Params -> Page.With Model Msg
page shared req =
    Page.advanced
        { init = init
        , update = update
        , view = view
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
    = ReplaceMe


update : Msg -> Model -> ( Model, Effect Msg )
update msg model =
    case msg of
        ReplaceMe ->
            ( model, Effect.none )



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.none



-- VIEW


view : Model -> View Msg
view model =
    View.placeholder "SignUp"

{-
module Pages.SignIn exposing (Model, Msg, page)

import Effect exposing (Effect)
import Element
    exposing
        ( Attribute
        , Element
        , alignLeft
        , centerX
        , centerY
        , column
        , el
        , fill
        , height
        , padding
        , paragraph
        , px
        , rgba
        , row
        , shrink
        , spaceEvenly
        , spacing
        , width
        )
import Element.Background exposing (color)
import Element.Border as Border
import Element.Font as Font
import Element.Input as Input exposing (button, labelAbove)
import Element.Region as Region exposing (heading)
import FontAwesome.Attributes as FontAttributes
import FontAwesome.Icon exposing (viewIcon, viewStyled)
import FontAwesome.Solid exposing (eye, eyeSlash)
import Gen.Params.SignIn exposing (Params)
import Page
import Request
import Shared as Shared exposing (JavascriptMethod(..))
import Validate exposing (Valid, Validator, ifBlank, ifFalse, ifInvalidEmail, ifTrue, validate)
import View exposing (View, dark, error, errorMessage, info, infoMessage, light, link, onEnter, successButton, text)


basePad :
    { top : Int
    , right : Int
    , bottom : Int
    , left : Int
    }
basePad =
    { top = 0
    , right = 0
    , bottom = 0
    , left = 0
    }


clearMessages : Model -> Model
clearMessages model =
    { model
        | info = Nothing
        , jsError = Nothing
        , errors = Nothing
    }


page : Shared.Model -> Request.With Params -> Page.With Model Msg
page _ _ =
    Page.advanced
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }


loginValidator : Validator String { username : String, password : String }
loginValidator =
    Validate.all
        [ ifBlank .username "Username is required"
        , ifBlank .password "Password is required"
        ]


signUpValidator : Validator String { username : String, password : String, confirmPassword : String, email : String }
signUpValidator =
    Validate.all
        [ ifBlank .username "Username is required"
        , Validate.firstError
            [ ifBlank .password "Password is required"
            , ifTrue (\m -> String.length m.password < 8) "Password must be at least 8 characters"
            ]
        , ifFalse (\model -> model.password == model.confirmPassword) "Passwords do not match"
        , Validate.firstError
            [ ifBlank .email "Email is required"
            , ifInvalidEmail .email (\_ -> "Email must be a valid email")
            ]
        ]


confirmCodeValidator : Validator String { username : String, code : String }
confirmCodeValidator =
    Validate.all
        [ ifBlank .code "Please enter the code sent to your email"
        , ifBlank .username "Username is required"
        ]


usernameValidator : Validator String { username : String }
usernameValidator =
    Validate.all [ ifBlank .username "Username is required" ]


emailValidator : Validator String { email : String }
emailValidator =
    Validate.firstError
        [ ifBlank .email "Email is required"
        , ifInvalidEmail .email (\_ -> "Email must be a valid email")
        ]


forgotPasswordValidator : Validator String { email : String, confirmationCode : String, password : String, confirmPassword : String }
forgotPasswordValidator =
    Validate.all
        [ ifBlank .email "You must provide your username"
        , ifBlank .confirmationCode "Please enter the code sent to your email"
        , Validate.firstError
            [ ifBlank .password "Password is required"
            , ifTrue (\m -> String.length m.password < 8) "Password must be at least 8 characters"
            ]
        , Validate.firstError
            [ ifBlank .confirmPassword "Please re-enter your new password"
            , ifFalse (\m -> m.password == m.confirmPassword) "Passwords do not match"
            ]
        ]



-- INIT


type alias Model =
    { username : String
    , password : String
    , email : String
    , confirmPassword : String
    , confirmationCode : String
    , showPassword : Bool
    , showConfirmPassword : Bool
    , jsError : Maybe String
    , errors : Maybe (List String)
    , info : Maybe String
    , state : State
    }


init : ( Model, Effect Msg )
init =
    ( Model "" "" "" "" "" False False Nothing Nothing Nothing LoggingIn, Effect.none )


type TextInput
    = Username
    | Password
    | ConfirmPassword
    | Email
    | ConfirmationCode


type State
    = LoggingIn
    | SignUpNewUser
    | AwaitingConfirmationCode
    | UserForgotPassword
    | NewPassword


type Toggles
    = ShowPassword
    | ShowConfirmPassword



-- UPDATE


type Msg
    = SetInput TextInput String
    | Login
    | GoogleLogin
    | SignUp
    | SetJsError (Maybe String)
    | SetInfo (Maybe String)
    | SignUpSuccess
    | ConfirmCode
    | ResendConfirmCode
    | SubmitPasswordReset
    | ForgotPasswordSubmit
    | SetState State
    | ToggleBool Toggles


update : Msg -> Model -> ( Model, Effect Msg )
update msg model =
    case msg of
        SetInput input setText ->
            case input of
                Username ->
                    ( { model | username = setText }, Effect.none )

                Email ->
                    ( { model | email = setText }, Effect.none )

                Password ->
                    ( { model | password = setText }, Effect.none )

                ConfirmPassword ->
                    ( { model | confirmPassword = setText }, Effect.none )

                ConfirmationCode ->
                    ( { model | confirmationCode = setText }, Effect.none )

        SetJsError message ->
            ( { model | jsError = message }, Effect.none )

        SetInfo message ->
            ( { model | info = message }, Effect.none )

        SetState state ->
            ( { model
                | state = state
                , password = ""
                , confirmPassword = ""
              }
                |> clearMessages
            , Effect.none
            )

        SignUp ->
            let
                validated =
                    validate signUpValidator
                        { username = model.username
                        , password = model.password
                        , confirmPassword = model.confirmPassword
                        , email = model.email
                        }
            in
            case validated of
                Err errors ->
                    ( { model | errors = Just errors }, Effect.none )

                Ok validModel ->
                    ( { model | errors = Nothing, password = "", confirmPassword = "" }
                    , Effect.fromShared <|
                        Shared.JavascriptCall <|
                            AuthSignUp validModel
                    )

        ConfirmCode ->
            let
                validated =
                    validate confirmCodeValidator { code = model.confirmationCode, username = model.username }
            in
            case validated of
                Err errors ->
                    ( { model
                        | errors = Just errors
                        , info = Nothing
                        , jsError = Nothing
                      }
                    , Effect.none
                    )

                Ok validModel ->
                    ( model |> clearMessages
                    , Effect.fromShared <|
                        Shared.JavascriptCall <|
                            ConfirmSignupCode validModel
                    )

        ResendConfirmCode ->
            let
                validated =
                    validate usernameValidator { username = model.username }
            in
            case validated of
                Err errors ->
                    ( { model | errors = Just errors }, Effect.none )

                Ok validModel ->
                    ( model |> clearMessages
                    , Effect.fromShared <|
                        Shared.JavascriptCall <|
                            ResendConfirmationCode validModel
                    )

        SubmitPasswordReset ->
            let
                validated =
                    validate emailValidator { email = model.email }
            in
            case validated of
                Err errors ->
                    ( { model | errors = Just errors }, Effect.none )

                Ok validModel ->
                    ( model |> clearMessages
                    , Effect.fromShared <|
                        Shared.JavascriptCall <|
                            RequestPasswordReset validModel
                    )

        ForgotPasswordSubmit ->
            let
                validated =
                    validate forgotPasswordValidator
                        { email = model.email
                        , password = model.password
                        , confirmPassword = model.confirmPassword
                        , confirmationCode = model.confirmationCode
                        }
            in
            case validated of
                Err errors ->
                    ( { model | errors = Just errors }, Effect.none )

                Ok validModel ->
                    ( model |> clearMessages
                    , Effect.fromShared <|
                        Shared.JavascriptCall <|
                            SubmitForgotPassword validModel
                    )

        SignUpSuccess ->
            ( { model | state = AwaitingConfirmationCode }, Effect.none )

        Login ->
            let
                validated =
                    validate loginValidator { username = model.username, password = model.password }
            in
            case validated of
                Err errors ->
                    ( { model | errors = Just errors, password = "" }, Effect.none )

                Ok validModel ->
                    ( { model | password = "" } |> clearMessages, Effect.fromShared <| Shared.JavascriptCall <| AuthLoginWithUsername validModel )

        GoogleLogin ->
            ( model, Effect.fromShared <| Shared.JavascriptCall LoginWithGoogle )

        ToggleBool toggle ->
            case toggle of
                ShowPassword ->
                    ( { model | showPassword = not model.showPassword }, Effect.none )

                ShowConfirmPassword ->
                    ( { model | showConfirmPassword = not model.showConfirmPassword }, Effect.none )



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ Shared.errorMessage (\err -> SetJsError <| Just err)
        , Shared.requestConfirmationCode (\_ -> SignUpSuccess)
        , Shared.infoMessage (\info -> SetInfo <| Just info)
        , Shared.continuePasswordReset (\info -> SetState NewPassword)
        , Shared.toLogin (\_ -> SetState LoggingIn)
        ]



-- VIEW


usernameElement : Model -> Element Msg
usernameElement model =
    Input.username []
        { onChange = SetInput Username
        , text = model.username
        , placeholder = Nothing
        , label = labelAbove [] <| text [ Font.size 15 ] "Username"
        }


passwordElement :
    (List (Attribute msg)
     ->
        { onChange : String -> Msg
        , text : String
        , placeholder : Maybe (Input.Placeholder msg)
        , label : Input.Label msg
        , show : Bool
        }
     -> Element Msg
    )
    -> Model
    -> Element Msg
passwordElement inputType model =
    row [ spacing 10, width fill ]
        [ inputType []
            { onChange = SetInput Password
            , text = model.password
            , placeholder = Nothing
            , label = labelAbove [] <| text [ Font.size 15 ] "Password"
            , show = model.showPassword
            }
        , button [ Element.moveDown 10 ]
            { onPress = Just <| ToggleBool ShowPassword
            , label =
                el [ Font.color light, width <| px 20 ]
                    (Element.html <|
                        viewStyled [ FontAttributes.lg ] <|
                            if model.showPassword then
                                eyeSlash

                            else
                                eye
                    )
            }
        ]


loginElement : Model -> Element Msg
loginElement model =
    row [ spacing 20, onEnter Login ]
        [ column [ Region.mainContent, width fill, spacing 5 ]
            [ usernameElement model
            , passwordElement Input.currentPassword model
            , link [ Font.size 15 ]
                { onPress = Just (SetState UserForgotPassword)
                , label = "Forgot password?"
                }
            , row [ spaceEvenly, width fill, Element.moveDown 10 ]
                [ Element.el [ Element.paddingEach { basePad | right = 15 }, width fill ] <|
                    successButton [ width fill ]
                        { onPress = Just Login
                        , label = "Sign In"
                        }
                , link [ Font.size 15 ]
                    { onPress = Just (SetState SignUpNewUser)
                    , label = "New? Create an account"
                    }
                ]
            ]
        , text [] "or"
        , column []
            [ {- Add social providers here -}
              button [ centerY ]
                { onPress = Just GoogleLogin
                , label =
                    text
                        [ Font.size 15
                        , Border.solid
                        , Border.color light
                        , Border.width 1
                        , padding 10
                        ]
                        "Login with Google"
                }
            ]
        ]


signUpElement : Model -> Element Msg
signUpElement model =
    column [ spacing 15, width fill, onEnter SignUp ]
        [ text [ heading 1 ] "Sign up for an account"
        , usernameElement model
        , Input.email []
            { onChange = SetInput Email
            , text = model.email
            , placeholder = Nothing
            , label = labelAbove [] <| text [ Font.size 15 ] "Email"
            }
        , passwordElement Input.newPassword model
        , row [ spacing 10, width fill ]
            [ Input.newPassword []
                { onChange = SetInput ConfirmPassword
                , text = model.confirmPassword
                , placeholder = Nothing
                , label = labelAbove [] <| text [ Font.size 15 ] "Confirm password"
                , show = model.showConfirmPassword
                }
            , button [ Element.moveDown 10 ]
                { onPress = Just <| ToggleBool ShowConfirmPassword
                , label =
                    el [ Font.color light, width <| px 20 ]
                        (Element.html <|
                            viewStyled [ FontAttributes.lg ] <|
                                if model.showConfirmPassword then
                                    eyeSlash

                                else
                                    eye
                        )
                }
            ]
        , row [ spaceEvenly, width fill, spacing 20 ]
            [ successButton [ width fill ]
                { onPress = Just SignUp
                , label = "Sign up"
                }
            , link [ Font.size 15 ]
                { onPress = Just (SetState LoggingIn)
                , label = "Already have an account? Log in"
                }
            ]
        ]


forgotPasswordElement : Model -> Element Msg
forgotPasswordElement model =
    row [ spacing 20 ]
        [ column [ Region.mainContent, width fill, spacing 20, onEnter SubmitPasswordReset ]
            [ text [ heading 1 ] "Please enter the email associated with your account"
            , column [ width fill, spacing 15 ]
                [ Input.email []
                    { onChange = SetInput Email
                    , text = model.email
                    , placeholder = Nothing
                    , label = labelAbove [] <| text [ Font.size 15 ] "Email"
                    }
                , successButton [ width fill ]
                    { onPress = Just SubmitPasswordReset
                    , label = "Submit"
                    }
                ]
            ]
        ]


newPasswordElement : Model -> Element Msg
newPasswordElement model =
    row [ spacing 20 ]
        [ column [ Region.mainContent, width fill, spacing 15, onEnter ForgotPasswordSubmit ]
            [ paragraph [ heading 1 ]
                [ text [] <|
                    "Please enter your new password for "
                        ++ model.email
                ]
            , paragraph []
                [ text [ Font.size 15 ] """
                    A confirmation code was sent to the email address provided.
                    Please enter it below to finish resetting your password
                  """
                ]
            , Input.text []
                { onChange = SetInput ConfirmationCode
                , text = model.confirmationCode
                , placeholder = Nothing
                , label = labelAbove [] <| text [ Font.size 15 ] "Confirmation Code"
                }
            , passwordElement Input.newPassword model
            , row [ spacing 10, width fill ]
                [ Input.newPassword []
                    { onChange = SetInput ConfirmPassword
                    , text = model.confirmPassword
                    , placeholder = Nothing
                    , label = labelAbove [] <| text [ Font.size 15 ] "Confirm password"
                    , show = model.showConfirmPassword
                    }
                , button [ Element.moveDown 10 ]
                    { onPress = Just <| ToggleBool ShowConfirmPassword
                    , label =
                        el [ Font.color light, width <| px 20 ]
                            (Element.html <|
                                viewStyled [ FontAttributes.lg ] <|
                                    if model.showConfirmPassword then
                                        eyeSlash

                                    else
                                        eye
                            )
                    }
                ]
            , successButton [ width fill ]
                { onPress = Just ForgotPasswordSubmit
                , label = "Submit New Password"
                }
            ]
        ]


confirmationCodeElement : Model -> Element Msg
confirmationCodeElement model =
    row [ spacing 20, onEnter ConfirmCode ]
        [ column [ Region.mainContent, width fill, spacing 20 ]
            [ column []
                [ text [ heading 1 ] "Enter your confirmation code"
                , paragraph []
                    [ text [ Font.size 15 ] """
                    A confirmation code was sent to the email address provided.
                    Please enter it below to finish signup
                  """
                    ]
                ]
            , column [ width fill, spacing 15 ]
                [ Input.text []
                    { onChange = SetInput ConfirmationCode
                    , text = model.confirmationCode
                    , placeholder = Nothing
                    , label = labelAbove [] <| text [ Font.size 15 ] "Confirmation Code"
                    }
                , successButton [ width fill ]
                    { onPress = Just ConfirmCode
                    , label = "Submit"
                    }
                , row [ spaceEvenly, width fill ]
                    [ link [ Font.size 15 ]
                        { onPress = Just ResendConfirmCode
                        , label = "Need a new code? Click here to resend"
                        }
                    , link [ Font.size 15 ]
                        { onPress = Just <| SetState LoggingIn
                        , label = "Back to Sign In"
                        }
                    ]
                ]
            ]
        ]


view : Model -> View Msg
view model =
    { title = "Sign In"
    , body =
        el [ width fill, height fill, color dark ] <|
            column [ centerX, centerY, spacing 10 ]
                [ el
                    [ width <| px 600
                    , centerX
                    , Border.width 2
                    , Border.solid
                    , Border.color <| rgba 0.9 0.9 0.9 0.3
                    , padding 40
                    ]
                  <|
                    case model.state of
                        LoggingIn ->
                            loginElement model

                        SignUpNewUser ->
                            signUpElement model

                        AwaitingConfirmationCode ->
                            confirmationCodeElement model

                        UserForgotPassword ->
                            forgotPasswordElement model

                        NewPassword ->
                            newPasswordElement model
                , case model.info of
                    Just modelInfo ->
                        info [] [ infoMessage [] modelInfo ]

                    Nothing ->
                        Element.none
                , let
                    localErrors =
                        Maybe.withDefault [] model.errors

                    allErrors =
                        Maybe.map (\err -> err :: localErrors) model.jsError
                            |> Maybe.withDefault localErrors
                  in
                  if List.isEmpty allErrors then
                    Element.none

                  else
                    error [] <| List.map (\err -> errorMessage [] err) allErrors
                ]
    }
 -}
