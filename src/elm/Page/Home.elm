port module Page.Home exposing (Model, Msg, init, subscriptions, toSession, update, view)

import Browser.Dom as Dom
import Html exposing (Html, br, button, div, form, h1, h3, i, input, label, li, p, text, ul)
import Html.Attributes exposing (attribute, class, for, id, name, type_, value)
import Html.Events exposing (onClick, onInput)
import Html.Keyed
import Json.Decode as Decode exposing (Decoder, Value, decodeValue, int, list, string)
import Json.Decode.Pipeline exposing (required)
import Session exposing (Session)
import Task as Task exposing (perform)
import Time as Time exposing (Posix)



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
    , expandParticipants : Bool
    }


init : Session -> ( Model, Cmd Msg )
init session =
    ( { session = session
      , currentlyAddingUser = False
      , users = []
      , selectedUser = Nothing
      , meetings = []
      , newUserName = ""
      , expandParticipants = False
      }
    , Cmd.none
    )



-- VIEW


renderKeyedUser : Maybe User -> User -> ( String, Html Msg )
renderKeyedUser selectedUser user =
    let
        classes =
            "list-group-item list-group-item-action"
                ++ (if Just user == selectedUser then
                        " active"

                    else
                        ""
                   )
    in
    ( user.id
    , button [ onClick (SelectUser user), class classes ]
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


participantView : Model -> List (Html Msg)
participantView model =
    [ div [ class "mt-4 mx-0 border border-primary row shadow-lg bg-accent" ]
        [ h1 [ class "col-auto mr-auto" ]
            [ text "Setup Participants"
            ]
        , button
            [ class "col-auto btn btn-lg"
            , attribute "data-toggle" "collapse"
            , attribute "data-target" "#participant-content"
            , onClick ToggleExpandParticipants
            ]
            [ text ((String.fromInt <| List.length <| model.users) ++ " Total")
            , let
                icon =
                    if model.expandParticipants then
                        "fa-chevron-up"

                    else
                        "fa-chevron-down"
              in
              i [ class ("ml-1 fas " ++ icon) ] []
            ]
        , div [ id "participant-content", class "collapse container-fluid" ]
            [ div [ class "row" ]
                [ p [ class "col-12" ] [ text "Use this area to add participants that will be involved in meetings. Add new participants and setup their availability by blocking out times on their weekly schedule." ]
                ]
            , div [ class "row" ]
                [ div [ class "col-12" ] [ newUserForm model ] ]
            , div [ class "row p-2" ]
                [ div [ class "col-12 p-0 pr-md-2 mb-2 mb-md-0 col-md-3" ]
                    [ newUserButton model
                    , Html.Keyed.ul [ class "list-group" ]
                        (List.map
                            (renderKeyedUser
                                model.selectedUser
                            )
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
                , div [ class "col-sm-12 col-md-9" ]
                    [ div [ class "row mb-2" ]
                        (case model.selectedUser of
                            Just user ->
                                [ h3 [ class "col-auto mr-auto" ] [ text (user.name ++ "'s Schedule:") ]
                                , button [ class "col-auto btn btn-danger", onClick (DeleteUser user) ]
                                    [ i [ class "fas fa-trash mr-1" ] []
                                    , text user.name
                                    ]
                                ]

                            Nothing ->
                                []
                        )
                    , div [ class "row" ]
                        [ div [ class "col-12 p-0", id "calendar" ] []
                        ]
                    ]
                ]
            ]
        ]
    ]


view : Model -> { title : String, content : Html Msg }
view model =
    { title = "Home"
    , content =
        div [ class "container-fluid" ]
            (participantView model)
    }



-- UPDATE


type Msg
    = SelectUser User
    | NewUser
    | UpdateUserName String
    | SaveUser
    | SaveUserWithId Time.Posix
    | ToggleExpandParticipants
    | LoadUsers Decode.Value
    | DeleteUser User
    | NoOp


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        NoOp ->
            ( model, Cmd.none )

        SelectUser s ->
            if model.selectedUser == Just s then
                ( model, Cmd.none )

            else
                ( { model | selectedUser = Just s }, loadUserWithEvents s )

        ToggleExpandParticipants ->
            ( { model | expandParticipants = not model.expandParticipants }, Cmd.none )

        DeleteUser u ->
            let
                filteredUsers =
                    List.filter (\user -> user /= u) model.users
            in
            ( { model | users = filteredUsers, selectedUser = Nothing }
            , Cmd.batch
                [ saveUsers filteredUsers
                , deleteUser u
                , destroyCalendar ()
                ]
            )

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
                    ( model, Cmd.none )

        SaveUser ->
            ( model, Task.perform SaveUserWithId Time.now )

        SaveUserWithId currentTimestamp ->
            let
                newUser =
                    { id =
                        String.fromInt <|
                            Time.posixToMillis currentTimestamp
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


port destroyCalendar : () -> Cmd msg


port deleteUser : User -> Cmd msg


port loadUserWithEvents : User -> Cmd msg
