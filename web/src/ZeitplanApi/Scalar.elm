-- Do not manually edit this file, it was auto-generated by dillonkearns/elm-graphql
-- https://github.com/dillonkearns/elm-graphql


module ZeitplanApi.Scalar exposing (Codecs, Id(..), Long(..), defaultCodecs, defineCodecs, unwrapCodecs, unwrapEncoder)

import Graphql.Codec exposing (Codec)
import Graphql.Internal.Builder.Object as Object
import Graphql.Internal.Encode
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode


type Id
    = Id String


type Long
    = Long String


defineCodecs :
    { codecId : Codec valueId
    , codecLong : Codec valueLong
    }
    -> Codecs valueId valueLong
defineCodecs definitions =
    Codecs definitions


unwrapCodecs :
    Codecs valueId valueLong
    ->
        { codecId : Codec valueId
        , codecLong : Codec valueLong
        }
unwrapCodecs (Codecs unwrappedCodecs) =
    unwrappedCodecs


unwrapEncoder :
    (RawCodecs valueId valueLong -> Codec getterValue)
    -> Codecs valueId valueLong
    -> getterValue
    -> Graphql.Internal.Encode.Value
unwrapEncoder getter (Codecs unwrappedCodecs) =
    (unwrappedCodecs |> getter |> .encoder) >> Graphql.Internal.Encode.fromJson


type Codecs valueId valueLong
    = Codecs (RawCodecs valueId valueLong)


type alias RawCodecs valueId valueLong =
    { codecId : Codec valueId
    , codecLong : Codec valueLong
    }


defaultCodecs : RawCodecs Id Long
defaultCodecs =
    { codecId =
        { encoder = \(Id raw) -> Encode.string raw
        , decoder = Object.scalarDecoder |> Decode.map Id
        }
    , codecLong =
        { encoder = \(Long raw) -> Encode.string raw
        , decoder = Object.scalarDecoder |> Decode.map Long
        }
    }
