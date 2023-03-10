module Calendar exposing
    ( CalendarState
    , Event
    , Model
    , Msg
    , Weekday
    , addEvent
    , dayString
    , dayToEvent
    , encodeEvent
    , init
    , isSaveMsg
    , stringToDay
    , timeRangeToDayString
    , timeToDayString
    , update
    , view
    )

import Array
import Effect exposing (Effect)
import FontAwesome as Icon
import FontAwesome.Solid as Icon
import Html exposing (Attribute, Html, button, div, p, span, table, tbody, td, text, th, thead, tr, wbr)
import Html.Attributes exposing (attribute, class, classList, style, type_)
import Html.Events exposing (onClick, onMouseDown, onMouseEnter, onMouseLeave, onMouseUp, stopPropagationOn)
import Json.Decode as Decode
import Json.Encode as Encode



-- VARS


ariaLabel : String -> Attribute msg
ariaLabel label =
    attribute "aria-label" label


const_interval : Int
const_interval =
    30


slots : Int
slots =
    minutesInDay // const_interval


type Weekday
    = Sunday
    | Monday
    | Tuesday
    | Wednesday
    | Thursday
    | Friday
    | Saturday
    | NotValidDay


stringToDay : String -> Weekday
stringToDay s =
    case s of
        "Sunday" ->
            Sunday

        "Monday" ->
            Monday

        "Tuesday" ->
            Tuesday

        "Wednesday" ->
            Wednesday

        "Thursday" ->
            Thursday

        "Friday" ->
            Friday

        "Saturday" ->
            Saturday

        _ ->
            NotValidDay


dayString : Weekday -> String
dayString d =
    case d of
        Sunday ->
            "Sunday"

        Monday ->
            "Monday"

        Tuesday ->
            "Tuesday"

        Wednesday ->
            "Wednesday"

        Thursday ->
            "Thursday"

        Friday ->
            "Friday"

        Saturday ->
            "Saturday"

        _ ->
            ""


days : Array.Array Weekday
days =
    Array.fromList [ Sunday, Monday, Tuesday, Wednesday, Thursday, Friday, Saturday ]


dayToEvent : Weekday -> Event
dayToEvent day =
    Array.toIndexedList days
        |> List.filterMap
            (\( index, weekday ) ->
                if weekday == day then
                    Just index

                else
                    Nothing
            )
        |> List.head
        |> Maybe.withDefault 0
        |> (\index -> Event (index * slots) ((index + 1) * slots) False [])


minutesInDay : Int
minutesInDay =
    60 * 24



-- TYPES


type alias Event =
    { start : Int
    , end : Int
    , dragging : Bool
    , classList : List ( String, Bool )
    }


encodeEvent : Event -> Encode.Value
encodeEvent e =
    Encode.object
        [ ( "start", Encode.int e.start )
        , ( "end", Encode.int e.end )
        ]


type alias EditEvent =
    { event : Event, shadowEvent : Maybe Event, time : Int }


type alias MoveEventEnd =
    { event : Event, end : Ends }



-- MODEL


type CalendarState
    = Resizing MoveEventEnd
    | Dragging EditEvent
    | Creating EditEvent
    | Idle


type alias Model =
    { events : List Event
    , state : CalendarState
    , blockedDays : List Weekday
    , overlayEvents : List Event
    , viewAllDayLine : Bool
    }



-- INIT


init : ( Model, Effect Msg )
init =
    ( { events = []
      , state = Idle
      , blockedDays = []
      , overlayEvents = []
      , viewAllDayLine = True
      }
    , Effect.none
    )



-- FUNCTIONS


timeSlotToString : Int -> String
timeSlotToString timeSlot =
    let
        timeInDay : Int
        timeInDay =
            const_interval * modBy slots (timeSlot - 1)

        time : Int
        time =
            modBy 60 timeInDay

        hour : Int
        hour =
            timeInDay // 60

        ( meridian, twelveHour ) =
            if hour > 12 then
                ( "PM", hour - 12 )

            else if hour == 12 then
                ( "PM", 12 )

            else if hour == 0 then
                ( "AM", 12 )

            else
                ( "AM", hour )
    in
    String.fromInt twelveHour ++ ":" ++ (String.padLeft 2 '0' <| String.fromInt time) ++ " " ++ meridian


timeToDayString : Int -> String
timeToDayString slot =
    Array.get (slot // slots) days
        |> Maybe.map dayString
        |> Maybe.withDefault ""


timeRangeToDayString : Int -> Int -> String
timeRangeToDayString startTimeslot endTimeslot =
    let
        startDayOfWeek : String
        startDayOfWeek =
            timeToDayString startTimeslot

        endDayOfWeek : String
        endDayOfWeek =
            timeToDayString endTimeslot

        startTime =
            timeSlotToString startTimeslot

        endTime =
            timeSlotToString (1 + endTimeslot)
    in
    if startDayOfWeek == endDayOfWeek then
        startDayOfWeek ++ " " ++ startTime ++ " - " ++ endTime

    else
        startDayOfWeek ++ " " ++ startTime ++ " - " ++ endDayOfWeek ++ " " ++ endTime


addEvent : Event -> List Event -> ( Event, List Event )
addEvent event list =
    let
        ( remainderEvents, conflictingEvents ) =
            List.partition (\ev -> ev.end < (event.start - 1) || ev.start > (1 + event.end)) list

        addedEvent : Event
        addedEvent =
            conflictingEvents
                |> List.foldl
                    (\ev ->
                        \n ->
                            { ev
                                | start = min ev.start n.start
                                , end = max ev.end n.end
                            }
                    )
                    event
    in
    ( addedEvent, addedEvent :: remainderEvents )



-- UPDATE


type Ends
    = Start
    | End


isSaveMsg : Msg -> Bool
isSaveMsg msg =
    case msg of
        DeleteEvent _ ->
            True

        EndCreateEvent ->
            True

        EndDragEvent ->
            True

        EndResizeEvent ->
            True

        ToggleAllDayBlock _ ->
            True

        _ ->
            False


type Msg
    = BeginCreateEvent Int
    | EndCreateEvent
    | MouseEnterTime Int
    | MouseLeaveCalendar
    | BeginDragEvent Event Int
    | DragEventTo Int
    | DeleteEvent Event
    | EndDragEvent
    | ResizeEvent Ends Event
    | ResizeEventTo Int
    | EndResizeEvent
    | ToggleAllDayBlock Weekday
    | NoOp


update : Msg -> Model -> ( Model, Effect Msg )
update msg model =
    case msg of
        NoOp ->
            ( model, Effect.none )

        ToggleAllDayBlock day ->
            let
                dayBlocked : Bool
                dayBlocked =
                    List.member day model.blockedDays

                blockedDays : List Weekday
                blockedDays =
                    if dayBlocked then
                        List.filter (\d -> d /= day) model.blockedDays

                    else
                        day :: model.blockedDays
            in
            ( { model | blockedDays = blockedDays }, Effect.none )

        MouseLeaveCalendar ->
            let
                clearEvents : Event -> Event
                clearEvents =
                    \event -> { event | dragging = False }
            in
            ( { model | events = List.map clearEvents model.events, state = Idle }, Effect.none )

        BeginCreateEvent t ->
            let
                event : Event
                event =
                    Event t t False []
            in
            ( { model | state = Creating { event = event, shadowEvent = Just event, time = t } }, Effect.none )

        EndCreateEvent ->
            case model.state of
                Creating { event } ->
                    let
                        ( _, newList ) =
                            addEvent event model.events
                    in
                    ( { model | events = newList, state = Idle }, Effect.none )

                _ ->
                    ( model, Effect.none )

        MouseEnterTime t ->
            case model.state of
                Creating { event, time } ->
                    let
                        ( newStart, newEnd ) =
                            if t < time then
                                ( t, time )

                            else
                                ( time, t )

                        newEvent : Event
                        newEvent =
                            { event | end = newEnd, start = newStart }
                    in
                    ( { model | state = Creating { event = newEvent, shadowEvent = Just newEvent, time = time } }, Effect.none )

                _ ->
                    ( model, Effect.none )

        BeginDragEvent event t ->
            let
                events : List Event
                events =
                    model.events
                        |> List.map
                            (\ev ->
                                if ev == event then
                                    { ev | dragging = True }

                                else
                                    ev
                            )
            in
            ( { model | events = events, state = Dragging { event = event, shadowEvent = Nothing, time = t } }, Effect.none )

        DragEventTo t ->
            case model.state of
                Dragging { event, time } ->
                    let
                        dragDistance : Int
                        dragDistance =
                            t - time

                        newEvent : Event
                        newEvent =
                            { event
                                | start = max 1 <| event.start + dragDistance
                                , end = min (slots * Array.length days) <| event.end + dragDistance
                            }
                    in
                    ( { model
                        | state =
                            Dragging
                                { event = newEvent
                                , shadowEvent = Just { newEvent | dragging = True }
                                , time = t
                                }
                      }
                    , Effect.none
                    )

                _ ->
                    ( model, Effect.none )

        EndDragEvent ->
            case model.state of
                Dragging { event } ->
                    let
                        ( _, newEvents ) =
                            addEvent { event | dragging = False } <|
                                List.filter (\current -> not current.dragging) model.events
                    in
                    ( { model | events = newEvents, state = Idle }, Effect.none )

                _ ->
                    ( model, Effect.none )

        DeleteEvent event ->
            let
                filterEvent : List Event -> List Event
                filterEvent =
                    List.filter (\pEvent -> pEvent /= event)
            in
            ( { model | events = filterEvent model.events }, Effect.none )

        ResizeEvent end event ->
            ( { model | state = Resizing { event = event, end = end } }, Effect.none )

        ResizeEventTo time ->
            case model.state of
                Resizing { event, end } ->
                    let
                        newEvent : Event
                        newEvent =
                            case end of
                                Start ->
                                    { event | start = min event.end time }

                                End ->
                                    { event | end = max event.start time }
                    in
                    ( { model
                        | state = Resizing { event = newEvent, end = end }
                        , events =
                            model.events
                                |> List.map
                                    (\e ->
                                        if e == event then
                                            newEvent

                                        else
                                            e
                                    )
                      }
                    , Effect.none
                    )

                _ ->
                    ( model, Effect.none )

        EndResizeEvent ->
            case model.state of
                Resizing { event } ->
                    let
                        ( _, newEvents ) =
                            addEvent event model.events
                    in
                    ( { model | events = newEvents, state = Idle }, Effect.none )

                _ ->
                    ( model, Effect.none )



-- VIEW


view : Model -> Html Msg
view model =
    let
        editEvent : Maybe Event
        editEvent =
            case model.state of
                Creating { shadowEvent } ->
                    shadowEvent

                Dragging { shadowEvent } ->
                    shadowEvent

                _ ->
                    Nothing

        ignoreEvent : String -> Attribute Msg
        ignoreEvent s =
            stopPropagationOn s <| Decode.succeed ( NoOp, True )

        viewDay : Weekday -> Html Msg
        viewDay day =
            th []
                [ span [ class "day-name" ]
                    [ text <| dayString day ]
                ]

        viewAllDay : Weekday -> Html Msg
        viewAllDay day =
            let
                isBlocked : Bool
                isBlocked =
                    List.member day model.blockedDays
            in
            td
                [ class "all-day-interval"
                , onClick <| ToggleAllDayBlock day
                , classList [ ( "all-day-blocked", isBlocked ) ]
                ]
                [ if isBlocked then
                    span [ class "icon-text" ]
                        [ span [ class "icon" ] [ Icon.view Icon.calendarMinus ]
                        , span [] [ text "Remove event" ]
                        ]

                  else
                    span [ class "icon-text" ]
                        [ span [ class "icon" ] [ Icon.view Icon.calendarPlus ]
                        , span [] [ text "Whole day event" ]
                        ]
                ]

        viewTime : Int -> Int -> Weekday -> Html Msg
        viewTime row column day =
            let
                blockedDay : Bool
                blockedDay =
                    List.member day model.blockedDays

                index : Int
                index =
                    slots * column + row

                matchingEvent : Maybe Event
                matchingEvent =
                    model.events
                        |> List.filter (\event -> index >= event.start && index <= event.end)
                        |> List.head

                matchingOverlay : Maybe Event
                matchingOverlay =
                    model.overlayEvents
                        |> List.filter (\event -> index >= event.start && index <= event.end)
                        |> List.head

                draftEvent : Maybe Event
                draftEvent =
                    editEvent
                        |> Maybe.andThen
                            (\event ->
                                if index >= event.start && index <= event.end then
                                    Just event

                                else
                                    Nothing
                            )

                viewDraft : Event -> Html Msg
                viewDraft event =
                    div
                        [ class "event draft"
                        , classList <|
                            [ ( "event-start", event.start == index )
                            , ( "event-end", event.end == index )
                            , ( "dragging", event.dragging )
                            ]
                                ++ event.classList
                        ]
                    <|
                        if event.start == index then
                            [ p [ class "event-time" ] [ text <| timeSlotToString event.start ++ " - " ++ timeSlotToString (1 + event.end) ] ]

                        else
                            []

                blockEvent : Attribute Msg -> Attribute Msg
                blockEvent attribute =
                    if blockedDay then
                        class "blocked"

                    else
                        attribute

                mouseEvents : List (Attribute Msg)
                mouseEvents =
                    if blockedDay then
                        []

                    else
                        case model.state of
                            Idle ->
                                [ onMouseDown <| BeginCreateEvent index ]

                            Creating _ ->
                                [ onMouseEnter <| MouseEnterTime index
                                , onMouseUp <| EndCreateEvent
                                ]

                            Dragging _ ->
                                [ onMouseEnter <| DragEventTo index
                                , onMouseUp <| EndDragEvent
                                ]

                            Resizing _ ->
                                [ onMouseEnter <| ResizeEventTo index
                                , onMouseUp <| EndResizeEvent
                                ]
            in
            td
                (classList
                    [ ( "first-row", row == 1 )
                    , ( "last-row", row == slots )
                    , ( "overlay-event", matchingOverlay /= Nothing )
                    , ( "blocked", blockedDay )
                    ]
                    :: mouseEvents
                )
            <|
                List.take 1 <|
                    List.reverse <|
                        (case matchingEvent of
                            Just event ->
                                [ div
                                    [ class "event"
                                    , classList <|
                                        [ ( "event-start", event.start == index )
                                        , ( "event-end", event.end == index )
                                        , ( "dragging", event.dragging )
                                        ]
                                            ++ event.classList
                                    , blockEvent <| stopPropagationOn "mousedown" (Decode.succeed ( BeginDragEvent event index, True ))
                                    ]
                                  <|
                                    if event.start == index || row == 1 then
                                        (if event.start == index then
                                            [ button
                                                [ class "event-resize"
                                                , blockEvent <| stopPropagationOn "mousedown" (Decode.succeed ( ResizeEvent Start event, True ))
                                                , ariaLabel "Resize start of event"
                                                ]
                                                []
                                            ]

                                         else
                                            []
                                        )
                                            ++ [ p [ class "event-time" ]
                                                    [ text <| timeSlotToString event.start ++ " - "
                                                    , wbr [] []
                                                    , text <| timeSlotToString (1 + event.end)
                                                    ]
                                               , button
                                                    [ blockEvent <| onClick <| DeleteEvent event
                                                    , ignoreEvent "mouseup"
                                                    , ignoreEvent "mousedown"
                                                    , class "event-close"
                                                    , ariaLabel "Delete event"
                                                    , type_ "button"
                                                    ]
                                                    [ Icon.view Icon.close ]
                                               ]

                                    else if event.end == index then
                                        [ button
                                            [ class "event-resize"
                                            , blockEvent <| stopPropagationOn "mousedown" (Decode.succeed ( ResizeEvent End event, True ))
                                            , ariaLabel "Resize end of event"
                                            ]
                                            []
                                        ]

                                    else
                                        []
                                ]

                            Nothing ->
                                []
                        )
                            ++ (draftEvent
                                    |> Maybe.map (viewDraft >> List.singleton)
                                    |> Maybe.withDefault []
                               )
    in
    table
        (class "calendar"
            :: class "week"
            :: (if model.state /= Idle then
                    [ onMouseLeave <| MouseLeaveCalendar ]

                else
                    []
               )
        )
        [ thead []
            [ tr [ class "week-header" ]
                (th [ class "time-header" ] []
                    :: (days
                            |> Array.map viewDay
                            |> Array.toList
                       )
                )
            ]
        , tbody []
            ((if model.viewAllDayLine then
                tr
                    [ class "all-day-row" ]
                    (td [] []
                        :: (days
                                |> Array.map viewAllDay
                                |> Array.toList
                           )
                    )

              else
                tr [ style "height" "10px" ] []
             )
                :: (List.range 1 slots
                        |> List.map
                            (\row ->
                                tr [] <|
                                    td [ class "display-time" ]
                                        [ p []
                                            [ text <| timeSlotToString row
                                            ]
                                        ]
                                        :: (days
                                                |> Array.indexedMap (viewTime row)
                                                |> Array.toList
                                           )
                            )
                   )
            )
        ]
