module Pages.Home_ exposing (Model, Msg, page)

import Dict
import Effect exposing (Effect)
import Gen.Params.Home_ exposing (Params)
import Html exposing (Html, a, br, button, div, em, h1, h2, h3, li, p, section, strong, text, ul)
import Html.Attributes exposing (class, classList, href, id, target)
import Html.Events exposing (onClick)
import Page
import Request exposing (Request)
import Shared
import Task
import Url.Builder exposing (Root(..), crossOrigin, custom, relative)
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
            ( Model SetupParticipants, Effect.none )

        Just "meetings" ->
            ( Model PreplanMeetings, Effect.none )

        Just "schedule" ->
            ( Model PlanSchedule, Effect.none )

        _ ->
            ( Model Overview, Effect.none )



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
    section [ class "section is-large" ]
        [ h1 [ class "title is-1" ] [ text "Who is this for?" ]
        , div [ class "box" ]
            [ h3 [ class "subtitle is-3" ] [ text "Use cases" ]
            , p [ class "content is-medium" ]
                [ text """
        Zeitplan was originally created for this use case: A University's Music Instructor's
        students and their schedules. "Participants" as we now call them originally were "students"; "meetings"
        were ensembles and private lessons; the "schedule" was posted by the instructor for students to
        adhere to all semester.
        """
                , br [] []
                , text """
        Since then, Zeitplan has come a long way to accomodate more and more use cases. As a scheduling application,
        it works great! If you think of something you'd like to see in this application, please 
        """
                , a
                    [ href <| crossOrigin "https://github.com" [ "TheLetterTheta", "Zeitplan", "issues" ] []
                    , target "_blank"
                    ]
                    [ text "check for an existing issue" ]
                , text " and consider showing support for it, or "
                , a
                    [ href <| crossOrigin "https://github.com" [ "TheLetterTheta", "Zeitplan", "issues", "new" ] []
                    , target "_blank"
                    ]
                    [ text "open your own issue" ]
                , text """
         and let us know how we can improve.
        """
                ]
            ]
        , h1 [ class "title is-1" ] [ text "Is this right for me?" ]
        , div [ class "box" ]
            [ h3 [ class "is-3 subtitle" ] [ text "Does your calendar already do this" ]
            , p [ class "content is-medium" ]
                [ text """
        Zeitplan is an excellent tool for what it does. Though there are many useful features for creating
        schedules, it may not be best suited for your specific needs.
        """
                , br [] []
                , text """
        Does it tell you when you can meet with one of your friends? Yes! Though, that feature exists in
        many other calendars you are probably already using. You're more than welcome to use Zeitplan as
        well, but it might not be the tool you're looking for.
        """
                , br [ class "block" ] []
                , text """
        Here's what Zeitplan offers:
        """
                , ul []
                    [ li [] [ text "Managing any number of participants" ]
                    , li [] [ text "Availability at a glance" ]
                    , li [] [ text "Easy scheduling of group events" ]
                    , li [] [ text "A scheduler that searches for a solution" ]
                    , li [] [ text "Reliable technology designed for stability and performance" ]
                    ]
                , text "A solution? To what exactly?"
                , br [] []
                , text "Well, check out our "
                , a [ href <| relative [ "about" ] [] ] [ text "about page" ]
                , text " for more details, but some schedules are definitely harder to manage than others"
                ]
            ]
        , br [] []
        , div [ class "box" ]
            [ h3 [ class "subtitle is-3" ] [ text "Sponsors" ]
            , p [ class "is-medium content" ]
                [ text "These are the people who have made Zeitplan possible."
                , ul []
                    [ li []
                        [ text "Professor Victor Drescher "
                        , a
                            [ href <| crossOrigin "https://dreschermusic.com" [] []
                            , target "_blank"
                            ]
                            [ text "(DrescherMusic.com)" ]
                        ]
                    ]
                , text "Want to be added? Consider "
                , a
                    [ href <| crossOrigin "https://github.com" [ "sponsors", "TheLetterTheta" ] []
                    , target "_blank"
                    ]
                    [ text "becoming a sponsor!" ]
                , text " Check the sponsor tiers for more information"
                ]
            ]
        ]


participantSection : Model -> Html Msg
participantSection model =
    section [ class "section is-large" ]
        [ h1 [ class "title is-1" ] [ text "Step 1" ]
        , div [ class "box" ]
            [ h3 [ class "is-3 subtitle" ] [ text "Who are the participants?" ]
            , p [ class "content is-medium" ]
                [ text """
            Anyone you need to meet with is considered a "participant". This does
            """
                , strong [] [ text " NOT " ]
                , text """
            include yourself. You are always considered one of the "participants". You can have as many participants
            setup as you want. Anyone who will need to be part of the schedule later should be setup.
            """
                ]
            ]
        , div [ class "box" ]
            [ h3 [ class "is-3 subtitle" ] [ text "Blocking times" ]
            , p [ class "content is-medium" ]
                [ text """
            Other people are busy too! They have things to do in their weeks - work, classes, other meetings. Zeitplan
            has a built in calendar for each participant to record these blocked times. When computing the final schedule,
            participants will not be able to be scheduled during these times.
            """
                ]
            ]
        , div [ class "box" ]
            [ h3 [ class "is-3 subtitle" ] [ text "What about groups?" ]
            , p [ class "content is-medium" ]
                [ text """
            Zeitplan can handle groups on its own. Do not worry about trying to find common times between the group members
            beforehand. This also makes it easier to schedule things such as private lessons, and group meetings with the
            same participant.
            """
                ]
            ]
        ]


meetingsSection : Model -> Html Msg
meetingsSection model =
    section [ class "section is-large" ]
        [ h1 [ class "title is-1" ] [ text "Step 2" ]
        , div [ class "box" ]
            [ h3 [ class "is-3 subtitle" ] [ text "What is a meeting?" ]
            , p [ class "content is-medium" ]
                [ text """
            Zeitplan considers a "meeting" to be anything which you need scheduled. Meetings have a duration (30, 60, 90, 120
            min.), a title (for identifying later), and participants. You can have one or more participants per meeting (for
            groups).
            """
                ]
            ]
        , div [ class "box" ]
            [ h3 [ class "is-3 subtitle" ] [ text "Limitations" ]
            , p [ class "content is-medium" ]
                [ text """
            Currently, meetings can only be scheduled in 30 minute intervals up to 2 hours in length. There is also no way
            to currently schedule a meeting 
              """
                , em [] [ text "X minutes after" ]
                , text """
                some other meeting (consider a recurring meeting every day). Given that there is only space for 1 week of
                times, there are a technical maximum of 336 meetings possible.
                """
                ]
            , p [ class "content is-medium" ]
                [ text """
            You can consider helping out these limitations by submitting an issue, or a Pull Request with a solution!
            """ ]
            ]
        ]


scheduleSection : Model -> Html Msg
scheduleSection model =
    section [ class "section is-large" ]
        [ h1 [ class "title is-1" ] [ text "Zeitplan!" ]
        , div [ class "box" ]
            [ h3 [ class "is-3 subtitle" ] [ text "Your Schedule" ]
            , p [ class "content is-medium" ]
                [ text """
                Here, put the times you're available to have all of these meetings. This is what Zeitplan will look
                through, to try to place your meetings.
              """
                ]
            , p [ class "content is-medium" ]
                [ text """
                This is not the times you can't meet. You're not blocking any times in this section. Why? It didn't
                feel very intuitive that way. If you'd like to meet between 8:00 - 10:00 on Monday, you would rather
                enter 8:00 - 10:00 on Monday, than block off Sunday @ 12:00 - Monday @ 8:00 AND Monday @ 10:00 - Saturday
                @ 12:00
            """ ]
            ]
        , div [ class "box" ]
            [ h3 [ class "is-3 subtitle" ] [ text "Make it yours" ]
            , p [ class "content is-medium" ]
                [ text """
                You're no longer spending hours trying to fit these meetings into your life. You no longer have to sacrifice
                your own schedule unnecessarilly just to make things easier.
              """
                ]
            , p [ class "content is-medium" ]
                [ text """
                From here, it's as easy as pressing a button - and letting Zeitplan handle the scheduling. Zeitplan will
                do its best (which turns out to be really good) to find that perfect schedule for you. So go ahead and
                try to give
            """
                , strong [] [ text "yourself" ]
                , text """
            the best schedule you can. If it didn't work, play with your avaialable times a bit more, and try again. It's
            as easy as pressing a button now. Each run should take a fraction of a second - often faster than humans can
            detect, even.
            """
                ]
            ]
        ]

type alias Section msg = {title: String, content: Html msg}
type alias Tab msg = {title: String, content: List (Section msg)}

renderTab: Tab msg -> Html msg
renderTab tab = 
    div [] []

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
                    [ h1 [ class "is-1 title" ] [ text "Zeitplan" ]
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
                            [ li [ id <| tabString Overview, classList <| [ ( "is-active", model.sectionTwo == Overview ) ] ]
                                [ a
                                    [ href <| custom Relative [] [] (Just <| tabString Overview)
                                    , onClick <| ChangeTab Overview
                                    ]
                                    [ text "Overview / Is this for me?" ]
                                ]
                            , li [ id <| tabString SetupParticipants, classList <| [ ( "is-active", model.sectionTwo == SetupParticipants ) ] ]
                                [ a
                                    [ href <| custom Relative [] [] (Just <| tabString SetupParticipants)
                                    , onClick <| ChangeTab SetupParticipants
                                    ]
                                    [ text "Setting up Participants" ]
                                ]
                            , li [ id <| tabString PreplanMeetings, classList <| [ ( "is-active", model.sectionTwo == PreplanMeetings ) ] ]
                                [ a
                                    [ href <| custom Relative [] [] (Just <| tabString PreplanMeetings)
                                    , onClick <| ChangeTab PreplanMeetings
                                    ]
                                    [ text "Preplan your Meetings" ]
                                ]
                            , li [ id <| tabString PlanSchedule, classList <| [ ( "is-active", model.sectionTwo == PlanSchedule ) ] ]
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
