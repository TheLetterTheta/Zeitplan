-- Do not manually edit this file, it was auto-generated by dillonkearns/elm-graphql
-- https://github.com/dillonkearns/elm-graphql


module GraphQLApi.Query exposing (..)

import GraphQLApi.InputObject
import GraphQLApi.Interface
import GraphQLApi.Object
import GraphQLApi.Scalar
import GraphQLApi.ScalarCodecs
import GraphQLApi.Union
import Graphql.Internal.Builder.Argument as Argument exposing (Argument)
import Graphql.Internal.Builder.Object as Object
import Graphql.Internal.Encode as Encode exposing (Value)
import Graphql.Operation exposing (RootMutation, RootQuery, RootSubscription)
import Graphql.OptionalArgument exposing (OptionalArgument(..))
import Graphql.SelectionSet exposing (SelectionSet)
import Json.Decode as Decode exposing (Decoder)


calendars :
    SelectionSet decodesTo GraphQLApi.Object.Calendar
    -> SelectionSet (List decodesTo) RootQuery
calendars object____ =
    Object.selectionForCompositeField "calendars" [] object____ (Basics.identity >> Decode.list)


meetings :
    SelectionSet decodesTo GraphQLApi.Object.Meeting
    -> SelectionSet (List decodesTo) RootQuery
meetings object____ =
    Object.selectionForCompositeField "meetings" [] object____ (Basics.identity >> Decode.list)


user :
    SelectionSet decodesTo GraphQLApi.Object.User
    -> SelectionSet decodesTo RootQuery
user object____ =
    Object.selectionForCompositeField "user" [] object____ Basics.identity
