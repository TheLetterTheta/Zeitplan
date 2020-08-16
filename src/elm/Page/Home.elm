port module Page.Home exposing (Model, Msg, init, subscriptions, toSession, update, view)

import Browser.Dom as Dom
import Html exposing (Html, br, button, div, form, h1, i, input, label, li, p, text, ul)
import Html.Attributes exposing (attribute, class, for, id, name, type_, value)
import Html.Events exposing (onClick, onInput)
import Html.Keyed
import Json.Decode as Decode exposing (Decoder, Value, decodeValue, int, list, string)
import Json.Decode.Pipeline exposing (required)
import Session exposing (Session)
import Task



-- MODEL


type alias User =
    { id : String
    , name : String
    }


type alias Meeting =
    { id : String
    , participantIds : List String
    , duration : Int
    }


type alias Model =
    { session : Session
    , users : List User
    , meetings : List Meeting
    , selectedUser : Maybe User
    , newUserName : String
    , currentlyAddingUser : Bool
    }


init : Session -> ( Model, Cmd Msg )
init session =
    ( { session = session
      , currentlyAddingUser = False
      , users = []
      , selectedUser = Nothing
      , meetings = []
      , newUserName = ""
      }
    , Cmd.none
    )



-- VIEW


renderKeyedUser : User -> ( String, Html Msg )
renderKeyedUser user =
    ( user.id
    , button [ onClick (SelectUser user), class "list-group-item list-group-item-action" ]
        [ text user.name ]
    )


newUserButton : Model -> Html Msg
newUserButton model =
    let
        ( buttonClass, buttonIcon, buttonText ) =
            if not model.currentlyAddingUser then
                ( "btn-success", "fa-user-plus", "Show" )

            else
                ( "btn-danger", "fa-user-times", "Hide" )

        classList =
            buttonClass ++ " list-group-item list-group-item-action text-center"
    in
    button
        [ id "new-user-btn"
        , attribute "data-toggle" "collapse"
        , attribute "data-target" "#new-user-form"
        , class classList
        , onClick NewUser
        ]
        [ i [ class ("fas " ++ buttonIcon) ] [], p [ class "m-0" ] [ text buttonText ] ]


newUserForm : Model -> Html Msg
newUserForm model =
    div [ class "collapse", id "new-user-form" ]
        [ div [ class "form-group" ]
            [ label [ for "name" ] [ text "Name" ]
            , div [ class "input-group" ]
                [ input [ type_ "text", value model.newUserName, onInput UpdateUserName, id "new-user-name-input", class "form-control" ] []
                , div [ class "input-group-append" ]
                    [ button [ onClick SaveUser, class "btn btn-success", type_ "submit" ] [ text "ADD" ] ]
                ]
            ]
        ]


view : Model -> { title : String, content : Html Msg }
view model =
    { title = "Home"
    , content =
        div [ class "container-fluid" ]
            [ h1 [] [ text "Configure Users" ]
            , div [ class "row" ]
                [ div [ class "col-12" ] [ newUserForm model ] ]
            , div [ class "row p-2" ]
                [ div [ class "col-12 p-0 pr-md-2 mb-2 mb-md-0 col-md-4" ]
                    [ newUserButton model
                    , Html.Keyed.ul [ class "list-group" ]
                        (List.map renderKeyedUser
                            (model.users
                                |> List.sortWith
                                    (\a ->
                                        \b ->
                                            compare
                                                (String.toLower a.name)
                                                (String.toLower b.name)
                                    )
                            )
                        )
                    ]
                , div [ class "col-sm-12 col-md-8" ]
                    [ div [ id "calendar" ] []
                    ]
                ]
            ]
    }



-- UPDATE


type Msg
    = SelectUser User
    | NewUser
    | UpdateUserName String
    | SaveUser
    | LoadUsers Decode.Value
    | NoOp


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        NoOp ->
            ( model, Cmd.none )

        SelectUser s ->
            ( { model | selectedUser = Just s }, Cmd.none )

        NewUser ->
            ( { model
                | newUserName = ""
                , currentlyAddingUser = not model.currentlyAddingUser
              }
            , Cmd.none
            )

        UpdateUserName name ->
            ( { model | newUserName = name }, Cmd.none )

        LoadUsers jsValue ->
            case decodeValue decodeUsers jsValue of
                Ok data ->
                    ( { model | users = data }, Cmd.none )

                Err error ->
                    ( { model
                        | users =
                            [ { id = "-1", name = Debug.toString error } ]
                      }
                    , Cmd.none
                    )

        SaveUser ->
            let
                newUser =
                    { id =
                        String.fromInt <|
                            List.length model.users
                    , name = model.newUserName
                    }

                shouldAdd =
                    String.trim model.newUserName /= ""

                newModel =
                    if shouldAdd then
                        { model
                            | users = newUser :: model.users
                            , newUserName = ""
                        }

                    else
                        model
            in
            ( newModel
            , Cmd.batch
                [ focusNewUserInput
                , saveUsers newModel.users
                ]
            )



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions _ =
    loadUsers LoadUsers



-- TASKS


focusNewUserInput : Cmd Msg
focusNewUserInput =
    Task.attempt (\_ -> NoOp) (Dom.focus "new-user-name-input")



-- EXPORT


toSession : Model -> Session
toSession model =
    model.session



-- PORTS


decodeUsers : Decoder (List User)
decodeUsers =
    Decode.list userDecoder


userDecoder : Decoder User
userDecoder =
    Decode.succeed User
        |> required "id" string
        |> required "name" string


port loadUsers : (Decode.Value -> msg) -> Sub msg


port saveUsers : List User -> Cmd msg
