module Decoders exposing (AuthUser, RefreshTokenPayload, SignUpResult, authUserDecoder, refreshTokenDecoder, signUpResultDecoder)

import Json.Decode as Decode
import Json.Decode.Pipeline exposing (optionalAt, required, requiredAt)



-- Required packages:
-- * elm/json
-- * NoRedInk/elm-json-decode-pipeline


type alias AuthUser =
    { userId : String
    , email : Maybe String
    , jwt : String
    , expiration : Int
    }


authUserDecoder : Decode.Decoder AuthUser
authUserDecoder =
    Decode.succeed AuthUser
        |> required "username" Decode.string
        |> optionalAt [ "attributes", "email" ] (Decode.nullable Decode.string) Nothing
        |> required "jwt" Decode.string
        |> required "expires" Decode.int


type alias SignUpResult =
    { userId : String
    , email : Maybe String
    , userConfirmed : Bool
    }


signUpResultDecoder : Decode.Decoder SignUpResult
signUpResultDecoder =
    Decode.succeed SignUpResult
        |> required "userSub" Decode.string
        |> optionalAt [ "user", "username" ] (Decode.nullable Decode.string) Nothing
        |> required "userConfirmed" Decode.bool


type alias RefreshTokenPayload =
    { jwt : String
    , expiration : Int
    }


refreshTokenDecoder : Decode.Decoder RefreshTokenPayload
refreshTokenDecoder =
    Decode.succeed RefreshTokenPayload
        |> required "jwt" Decode.string
        |> required "expires" Decode.int
