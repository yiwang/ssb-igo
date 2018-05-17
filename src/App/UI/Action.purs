module App.UI.Action where

import Prelude

import App.IgoMsg (IgoMsg(OfferMatch), OfferMatchPayload)
import App.IgoMsg as Msg
import App.Streaming (decodeFlumeDb, mapFn, maybeToFlumeState, reduceFn)
import App.UI.Effect (Effect(..))
import App.UI.Model (DevIdentity, FlumeState(..), Model)
import Data.Argonaut (Json, jsonNull)
import Data.Maybe (Maybe(..), maybe)
import Debug.Trace (spy, traceAny)
import Spork.App (lift, purely)
import Spork.App as App
import Ssb.Types (UserKey)

data Action
  = Noop
  | UpdateFlume Json
  | UpdateIdentity {id :: UserKey}
  | PlaceStone
  | CreateOffer UserKey OfferMatchPayload
  | SetDevIdentity (DevIdentity)

update ∷ Model -> Action -> App.Transition Effect Model Action
update model = case _ of
  Noop ->
    App.purely model
  UpdateIdentity {id} ->
    App.purely $ model { whoami = Just id }
  UpdateFlume json ->
    App.purely $ case model.flume, decodeFlumeDb json of
      FlumeFailure _, _ -> model
      _, Just db -> model { flume = FlumeDb db }
      FlumeUnloaded, Nothing -> model { flume = FlumeFailure "Flume index not intitialized"}
      FlumeDb flume, Nothing ->
        let mapped = mapFn json
        in if spy $ mapped == jsonNull
          then model
          else model { flume = FlumeDb $ reduceFn flume mapped }
  PlaceStone ->
    { model, effects: lift (Publish model.devIdentity (Msg.demoMsg) Noop) }
  CreateOffer opponent payload ->
    let msg = OfferMatch payload
    in { model, effects: lift (Publish model.devIdentity msg Noop)}
  SetDevIdentity ident ->
    { model: model { devIdentity = Just ident }
    , effects: lift (GetIdentity (Just ident) UpdateIdentity)
    }
