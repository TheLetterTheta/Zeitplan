module MainTests exposing (meetingDecoderTest, resultDecoderTest, timeslotDecoderTest, userDecoderTest)

import Dict exposing (Dict)
import Expect exposing (Expectation)
import Fuzz exposing (Fuzzer, int, list, string)
import Json.Decode as Decode exposing (decodeString)
import Main exposing (Meeting, MeetingTimeslot, ResultStatus, User, decodeMeetings, decodeResults, decodeTimeslots, decodeUsers)
import Test exposing (..)


resultDecoderTest : Test
resultDecoderTest =
    test "Properly decodes computed schedule results" <|
        \() ->
            let
                input =
                    """
                                {
                                        "randomIdString": {
                                                "status": "Scheduled",
                                                "time": "Monday at 2:30 - 3:00 P.M.",
                                                "ord": 3
                                        }
                                }
                                """

                decoderOutput =
                    Decode.decodeString decodeResults input
            in
            Expect.equal decoderOutput
                (Ok
                    (Dict.fromList
                        [ ( "randomIdString", ResultStatus "Scheduled" "Monday at 2:30 - 3:00 P.M." 3 ) ]
                    )
                )


timeslotDecoderTest : Test
timeslotDecoderTest =
    test "Properly decodes timeslots" <|
        \() ->
            let
                input =
                    """
                    {
                            "randomIdString" : [ 
                                    {
                                        "ord": 4,
                                        "time": "Monday at 3:00-3:30"
                                    }
                            ]
                    }
                    """

                decoderOutput =
                    Decode.decodeString decodeTimeslots input
            in
            Expect.equal decoderOutput
                (Ok
                    (Dict.fromList
                        [ ( "randomIdString", [ MeetingTimeslot 4 "Monday at 3:00-3:30" ] )
                        ]
                    )
                )


meetingDecoderTest : Test
meetingDecoderTest =
    test "Properly parses meetings list" <|
        \() ->
            let
                input =
                    """
                [
                        { "id": "Test"
                        , "title": "TitleTest"
                        , "participantIds": [ "p1", "p2", "p3" ]
                        , "duration": 2
                        }
                ]
                """

                decoderOutput =
                    Decode.decodeString decodeMeetings input
            in
            Expect.equal decoderOutput
                (Ok
                    [ Meeting "Test" "TitleTest" [ "p1", "p2", "p3" ] 2 False
                    ]
                )


userDecoderTest : Test
userDecoderTest =
    test "Properly decodes users/participants" <|
        \() ->
            let
                input =
                    """
                        [
                                { "id": "user1"
                                , "name": "test user"
                                }
                        ]       
                        """

                decoderOutput =
                    Decode.decodeString decodeUsers input
            in
            Expect.equal decoderOutput
                (Ok
                    [ User "user1" "test user"
                    ]
                )
