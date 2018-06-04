module App.Streaming where

import Prelude

import App.Common (messageTypeString)
import App.IgoMsg (AcceptMatchPayload, BoardPosition(..), DeclineMatchPayload, IgoMove(..), IgoMsg(..), MsgKey, OfferMatchPayload, PlayMovePayload, RequestMatchPayload, SsbIgoMsg(..), StoneColor(..), parseIgoMessage)
import App.UI.Model (FlumeData, FlumeState(..), IndexedDecline(..), IndexedMatch(..), IndexedMove(..), IndexedOffer(..), IndexedRequest(..), MoveStep(..), addUserKey, assignColors')
import App.Utils (trace', (&))
import Control.Alt ((<|>))
import Data.Argonaut (Json, fromObject, jsonNull, toObject, toString)
import Data.Argonaut.Generic.Argonaut (decodeJson, encodeJson)
import Data.Array (last, length, snoc)
import Data.Bifunctor (lmap)
import Data.Either (Either(..), either, hush)
import Data.Foreign (Foreign, toForeign)
import Data.Function.Uncurried (Fn2)
import Data.Generic (class Generic, gEq, gShow)
import Data.Maybe (Maybe(..), fromJust, fromMaybe, maybe)
import Data.Newtype (class Newtype, unwrap, wrap)
import Data.Record as Record
import Data.StrMap (StrMap, delete, fromFoldable, insert, lookup)
import Data.StrMap as M
import Data.Symbol (SProxy(..))
import Data.Traversable (sequence)
import Data.Tuple (Tuple(..))
import Data.Tuple.Nested ((/\))
import Debug.Trace (spy, trace, traceA, traceAny, traceAnyA)
import Global.Unsafe (unsafeStringify)
import Partial (crashWith)
import Partial.Unsafe (unsafeCrashWith, unsafePartial)
import Ssb.Types (UserKey, MessageKey)



decodeFlumeDb :: Json -> Maybe FlumeData
decodeFlumeDb json = do
  o <- toObject json
  offers <- M.lookup "offers" o >>= toObject >>= (map (decodeJson >>> hush) >>> sequence)
  requests <- M.lookup "requests" o >>= toObject >>= (map (decodeJson >>> hush) >>> sequence)
  declines <- M.lookup "declines" o >>= toObject >>= (map (decodeJson >>> hush) >>> sequence)
  matches <- M.lookup "matches" o >>= toObject >>= (map (decodeJson >>> hush) >>> sequence)
  moves <- M.lookup "moves" o >>= toObject >>= (map (decodeJson >>> hush) >>> sequence)
  pure $ { offers, requests, declines, matches, moves }

maybeToFlumeState :: String -> Maybe FlumeData -> FlumeState
maybeToFlumeState err = maybe (FlumeFailure err) FlumeDb

encodeFlumeDb :: FlumeData -> Json
encodeFlumeDb db =
  fromObject $ fromFoldable
    [ "offers" & (fromObject $ map encodeJson db.offers)
    , "requests" & (fromObject $ map encodeJson db.requests)
    , "declines" & (fromObject $ map encodeJson db.declines)
    , "matches" & (fromObject $ map encodeJson db.matches)
    , "moves" & (fromObject $ map encodeJson db.moves)
    ]

type ReduceFn = FlumeData -> Json -> FlumeData
type ReduceFnImpl = Fn2 Json Json Json
type MapFn = Json -> Json

data MessageType
  = ValidPayload Json
  | PrivateMessage
  | InvalidMessage


reduceFn :: ReduceFn
reduceFn (db) json =
  reduceRight $ case _ of

    Tuple (RequestMatch payload) {key, author} ->
      db { requests = insert key (IndexedRequest payload {key, author}) db.requests }

    Tuple (ExpireRequest targetKey) {author} ->
      lookup targetKey db.requests
        # maybe db \(IndexedRequest _ meta) ->
          if author == meta.author
            then db { requests = delete targetKey db.requests }
            else db

    Tuple (OfferMatch payload) {key, author} ->
      db { offers = insert key (IndexedOffer payload {key, author}) db.offers }

    Tuple (WithdrawOffer targetKey) {author} ->
      lookup targetKey db.offers
        # maybe db \(IndexedOffer _ meta) ->
          if author == meta.author
            then db { offers = delete targetKey db.offers }
            else db

    Tuple (AcceptMatch acceptPayload@{offerKey}) acceptMeta@{key} ->
      lookup offerKey db.offers
        # maybe db \(IndexedOffer offerPayload@{opponentKey} offerMeta) ->
          if acceptMeta.author == opponentKey
            then
              let match = IndexedMatch
                            { acceptPayload
                            , offerPayload
                            , moves: []
                            , acceptMeta: {author: acceptMeta.author, key: acceptMeta.key}
                            , offerMeta: {author: offerMeta.author, key: offerMeta.key}
                            }
              in db { offers = delete offerKey db.offers
                    , matches = insert key match db.matches
                    }
            else db

    Tuple (DeclineMatch payload@{offerKey}) {key, author} ->
      lookup offerKey db.offers
        # maybe db \(IndexedOffer {opponentKey} meta) ->
          if author == opponentKey
            then
              let payload' = addUserKey meta.author payload
              in db { offers = delete offerKey db.offers
                    , declines = insert key (IndexedDecline payload' {key, author}) db.declines
                    }
            else db

    Tuple (AcknowledgeDecline targetKey) {author} ->
      lookup targetKey db.declines
        # maybe db \(IndexedDecline {userKey} meta) ->
          if author == userKey
            then db { declines = delete targetKey db.declines }
            else db

    Tuple (PlayMove payload@{move, lastMove}) {author, key} ->
      let maybeMatch =
            case M.lookup lastMove db.moves, M.lookup lastMove db.matches of
              Nothing, Just match ->
                Just match
              Just (IndexedMove _ {rootAccept} _), Nothing ->
                M.lookup rootAccept db.matches
              _, _ -> Nothing  -- NB: also handles case of Just, Just, which is absurd
      in case maybeMatch of
        Nothing ->
          trace ("invalid message chain") $ const db
        Just match@(IndexedMatch {acceptMeta}) ->
          let rootAccept = acceptMeta.key
              moveError = validateMove match payload author
          in case moveError of
            Nothing ->
              let
                newMove = IndexedMove payload {rootAccept} {key, author}
                moveStep = MoveStep {move, key}
                newMatch = match # unwrap >>> (\m -> m { moves = snoc m.moves moveStep }) >>> wrap
              in db { moves   = M.insert key newMove db.moves
                    , matches = M.insert rootAccept newMatch db.matches }
            Just err ->
              trace ("move validation error: " <> err) $ const db


    Tuple (Kibitz payload) _ ->
      trace' "TODO" db

  where

    msg = parseIgoMessage json # lmap \err -> trace ("bad message: " <> err <> ". json = " <> show json)
    reduceRight f = either (const db) (f <<< \m -> Tuple m.content m) msg

    lastMoveKey :: IndexedMatch -> Maybe MessageKey
    lastMoveKey (IndexedMatch {moves}) = (_.key <<< unwrap) <$> last moves

    nextMover :: IndexedMatch -> UserKey
    nextMover match@(IndexedMatch {offerPayload, offerMeta}) =
      method2
      where
        {author} = offerMeta
        {terms, myColor, opponentKey} = offerPayload
        {handicap} = terms
        firstMover = if (myColor == Black) == (handicap == 0)
                        then author
                        else opponentKey
        method2 = case flip M.lookup db.moves =<< lastMoveKey match of
                    Just (IndexedMove _ _ lastMeta) -> if author == lastMeta.author then opponentKey else author
                    Nothing -> firstMover

    validateMove :: IndexedMatch -> PlayMovePayload -> UserKey -> Maybe String
    validateMove match@(IndexedMatch {offerPayload, offerMeta, moves}) {move, lastMove} author =
      validateLastMove <|> validatePlayer
      where
        {terms, myColor} = offerPayload
        {handicap} = terms
        {black, white} = getPlayers match
        validateLastMove = lastMoveKey match >>= \key ->
          if spy key == spy lastMove
          then Nothing
          else Just $ "move is not in response to last valid move! "
                   <> author <> " || "
                   <> key
        validatePlayer = case move of
          Resign -> Nothing
          _ -> if author == nextMover match then Nothing else Just $ "not your turn to move! " <> author

    getPlayers :: IndexedMatch -> {black :: UserKey, white :: UserKey}
    getPlayers (IndexedMatch {offerPayload, offerMeta}) =
      assignColors' offerPayload offerMeta

mapFn :: MapFn
mapFn json = if isValidMessage json then json else trace' ("dropped message: " <> show json) jsonNull

isValidMessage :: Json -> Boolean
isValidMessage json = maybe false ((==) messageTypeString) (messageType json)

messageType :: Json -> Maybe String
messageType json = toObject json
  >>= lookup "value" >>= toObject
  >>= lookup "content" >>= toObject
  >>= lookup "type" >>= toString
