module Pages.Home_ exposing (Model, Msg, page)

import Debug
import Dict
import Effect exposing (Effect)
import Gen.Params.Home_ exposing (Params)
import Html exposing (Html, a, button, div, h1, h2, h3, li, p, section, strong, text, ul)
import Html.Attributes exposing (class, classList, href, id)
import Html.Events exposing (onClick)
import Page
import Request exposing (Request)
import Shared
import Task
import Url.Builder exposing (Root(..), custom, relative)
import View exposing (View, container, content, footer, role, zeitplanNav)


page : Shared.Model -> Request.With Params -> Page.With Model Msg
page shared req =
    Page.advanced
        { init = init req
        , update = update
        , view = view shared
        , subscriptions = subscriptions
        }



-- INIT


type alias Model =
    { sectionTwo : TabView
    , debugInfo : String
    }


type TabView
    = Overview
    | SetupParticipants
    | PreplanMeetings
    | PlanSchedule


init : Request.With Params -> ( Model, Effect Msg )
init req =
    case req.url.fragment of
        Just "participants" ->
            ( Model SetupParticipants (Debug.toString req), Effect.none )

        Just "meetings" ->
            ( Model PreplanMeetings (Debug.toString req), Effect.none )

        Just "schedule" ->
            ( Model PlanSchedule (Debug.toString req), Effect.none )

        _ ->
            ( Model Overview (Debug.toString req), Effect.none )



-- UPDATE


type Msg
    = SharedMsg Shared.Msg
    | ChangeTab TabView
    | NoOp


tabString : TabView -> String
tabString tab =
    case tab of
        Overview ->
            "overview"

        SetupParticipants ->
            "participants"

        PreplanMeetings ->
            "meetings"

        PlanSchedule ->
            "schedule"


update : Msg -> Model -> ( Model, Effect Msg )
update msg model =
    case msg of
        ChangeTab tab ->
            ( { model | sectionTwo = tab }, Effect.fromShared <| Shared.ScrollToElement <| tabString tab )

        SharedMsg sharedMsg ->
            ( model, Effect.fromShared sharedMsg )

        NoOp ->
            ( model, Effect.none )



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.none



-- VIEW


overviewSection : Model -> Html Msg
overviewSection model =
    section [ id <| tabString Overview, class "section is-large" ]
        [ h1 [ class "title" ] [ text "Is this right for me?" ]
        , h2 [ class "subtitle" ] [ text "Does your calendar already do this" ]
        , div [ class "box content" ]
            [ p []
                [ text """
        Zeitplan is an excellent tool for what it does. Though there are many useful features for creating
        schedules, it may not be best suited for your specific needs.
        """
                ]
            , p []
                [ text """
        Does it tell you when you can meet with one of your friends? Yes! Though, that feature exists in
        many other calendars you are probably already using. You're more than welcome to use Zeitplan as
        well, but it might not be the tool you're looking for.
        """
                , p []
                    [ text """
        Here's what Zeitplan offers:
        """
                    , ul []
                        [ li [] [ text "Managing any number of participants" ]
                        , li [] [ text "Availability at a glance" ]
                        , li [] [ text "Easy scheduling of group events" ]
                        , li [] [ text "A scheduler that searches for a solution" ]
                        , li [] [ text "Reliable technology designed for stability and performance" ]
                        ]
                    ]
                , p [] [ text "A solution? To what exactly?" ]
                , p []
                    [ text "Well, check out our "
                    , a [ href <| relative [ "about" ] [] ] [ text "about page" ]
                    , text " for more details, but some schedules are definitely harder to manage than others"
                    ]
                ]
            ]
        ]


participantSection : Model -> Html Msg
participantSection model =
    section [ id <| tabString SetupParticipants, class "section is-large" ]
        [ h1 [ class "title" ] [ text "Step 1 - Participants" ]
        , h2 [ class "subtitle" ] [ text "Who do you need to meet with?" ]
        ]


meetingsSection : Model -> Html Msg
meetingsSection model =
    section [ id <| tabString PreplanMeetings, class "section is-large" ]
        [ h1 [ class "title" ] [ text "Step 2 - Meetings" ]
        , h2 [ class "subtitle" ] [ text "Where to put those participants" ]
        ]


scheduleSection : Model -> Html Msg
scheduleSection model =
    section [ id <| tabString PlanSchedule, class "section is-large" ]
        [ h1 [ class "title" ] [ text "Finally - The Magic" ]
        , h2 [ class "subtitle" ] [ text "Schedule! Zeitplan!" ]
        ]


view : Shared.Model -> Model -> View Msg
view shared model =
    { title = "Zeitplan - Home"
    , body =
        [ zeitplanNav
            { logo = shared.logo
            , shared = shared
            }
            |> Html.map
                (\navMsg ->
                    case navMsg of
                        View.ToggleHamburger ->
                            SharedMsg Shared.ToggleNavbarHamburger

                        View.Logout ->
                            SharedMsg Shared.Logout
                )
        , section [ class "hero is-fullheight-with-navbar is-dark" ]
            [ div [ class "hero-head" ]
                [ div [ class "section" ]
                    [ h1 [ class "title" ] [ text "Zeitplan" ]
                    , p [ class "subtitle" ] [ text "A different kind of scheduler" ]
                    ]
                ]
            , div [ class "hero-body" ]
                [ div [ class "container" ]
                    [ h3 [ class "title" ]
                        [ text "Does this describe you?" ]
                    , div [ class "content" ]
                        [ ul []
                            [ li [ class "subtitle" ] [ text """
                            Are you spending too much time trying to fit everyone into your schedule?
                            """ ]
                            , li [ class "subtitle" ] [ text """
                            Do you need to setup a schedule that's more complex than your calendar currently
                            helps you with?
                            """ ]
                            , li [ class "subtitle" ]
                                [ text """
                            Have you ever settled for a schedule that asked too much of
                            """
                                , strong [] [ text "you" ]
                                , text " because you had given up?"
                                ]
                            , li [ class "subtitle" ] [ text """
                            Have you ever asked yourself, "There has to be an easier way to plan all these things!"
                            """ ]
                            ]
                        ]
                    ]
                ]
            , div [ class "hero-foot" ]
                [ div [ class "tabs is-large is-boxed is-fullwidth" ]
                    [ div [ class "container" ]
                        [ ul []
                            [ li [ classList <| [ ( "is-active", model.sectionTwo == Overview ) ] ]
                                [ a
                                    [ href <| custom Relative [] [] (Just <| tabString Overview)
                                    , onClick <| ChangeTab Overview
                                    ]
                                    [ text "Overview / Is this for me?" ]
                                ]
                            , li [ classList <| [ ( "is-active", model.sectionTwo == SetupParticipants ) ] ]
                                [ a
                                    [ href <| custom Relative [] [] (Just <| tabString SetupParticipants)
                                    , onClick <| ChangeTab SetupParticipants
                                    ]
                                    [ text "Setting up Participants" ]
                                ]
                            , li [ classList <| [ ( "is-active", model.sectionTwo == PreplanMeetings ) ] ]
                                [ a
                                    [ href <| custom Relative [] [] (Just <| tabString PreplanMeetings)
                                    , onClick <| ChangeTab PreplanMeetings
                                    ]
                                    [ text "Preplan your Meetings" ]
                                ]
                            , li [ classList <| [ ( "is-active", model.sectionTwo == PlanSchedule ) ] ]
                                [ a
                                    [ href <| custom Relative [] [] (Just <| tabString PlanSchedule)
                                    , onClick <| ChangeTab PlanSchedule
                                    ]
                                    [ text "Plan your schedule" ]
                                ]
                            ]
                        ]
                    ]
                ]
            ]
        , case model.sectionTwo of
            Overview ->
                overviewSection model

            SetupParticipants ->
                participantSection model

            PreplanMeetings ->
                meetingsSection model

            PlanSchedule ->
                scheduleSection model
        , footer
        ]
    }
