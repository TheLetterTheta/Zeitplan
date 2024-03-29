-- Do not manually edit this file, it was auto-generated by dillonkearns/elm-graphql
-- https://github.com/dillonkearns/elm-graphql


module ZeitplanApi.Object.Schedules exposing (..)

import Graphql.Internal.Builder.Argument as Argument exposing (Argument)
import Graphql.Internal.Builder.Object as Object
import Graphql.Internal.Encode as Encode exposing (Value)
import Graphql.Operation exposing (RootMutation, RootQuery, RootSubscription)
import Graphql.OptionalArgument exposing (OptionalArgument(..))
import Graphql.SelectionSet exposing (SelectionSet)
import Json.Decode as Decode
import ZeitplanApi.InputObject
import ZeitplanApi.Interface
import ZeitplanApi.Object
import ZeitplanApi.Scalar
import ZeitplanApi.ScalarCodecs
import ZeitplanApi.Union


data :
    SelectionSet decodesTo ZeitplanApi.Object.ScheduleResponse
    -> SelectionSet (List decodesTo) ZeitplanApi.Object.Schedules
data object____ =
    Object.selectionForCompositeField "data" [] object____ (Basics.identity >> Decode.list)


nextToken : SelectionSet (Maybe String) ZeitplanApi.Object.Schedules
nextToken =
    Object.selectionForField "(Maybe String)" "nextToken" [] (Decode.string |> Decode.nullable)
