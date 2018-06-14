module App.UI.Action where

import Prelude

import App.Flume (FlumeState(..), IndexedMatch(..), decodeFlumeDb, mapFn, reduceFn)
import App.IgoMsg (GameTerms, IgoMsg(..), KibitzPayload, OfferMatchPayload)
import App.UI.Effect (Affect, Effect, runEffect)
import App.UI.Effect as E
import App.UI.Model (DevIdentity, Model)
import App.UI.Optics (ModelLens)
import App.UI.Optics as O
import App.UI.Routes (Route(..))
import Control.Monad.Aff.Console as Aff
import Control.Monad.Eff.Class (liftEff)
import DOM (DOM)
import DOM.Classy.Element (fromElement)
import DOM.Classy.HTMLElement (fromHTMLElement)
import DOM.Classy.Node (nodeValue)
import DOM.HTML.HTMLInputElement (setValue, value)
import DOM.Node.Types (Element)
import Data.Argonaut (Json, decodeJson, jsonNull)
import Data.Array (last)
import Data.Either (Either(Right, Left))
import Data.Lens (set)
import Data.Maybe (Maybe(..), maybe)
import Data.Newtype (unwrap)
import Data.StrMap as M
import Debug.Trace (spy, traceA, traceAnyA)
import Halogen.VDom.DOM.Prop (ElemRef(..))
import Spork.App (lift, purely)
import Spork.App as App
import Spork.Html (ElementRef)
import Ssb.MessageTypes (AboutMessage(..))
import Ssb.Types (UserKey, MessageKey)
import Tenuki.Game (TenukiGame, setGameState)
import Tenuki.Game as Tenuki

data Action
  = Noop
  | SetRoute Route
  | UpdateFlume Json
  | UpdateFriends Json
  | UpdateIdentity {id :: UserKey}
  -- | UpdateScratch Event (String -> ScratchOffer)
  | CreateOffer OfferMatchPayload
  | Publish IgoMsg
  | SetDevIdentity (DevIdentity)

  | ManageRef String ElementRef
  | ManageTenukiGame IndexedMatch ElementRef
  | SetTenukiGame (Maybe TenukiGame)
  | SubmitKibitz MessageKey
  | UpdateModel (Model -> Model)
  | UpdateField' (String -> Either String (Model -> Model)) String

  | HandlePlayerAutocomplete (ModelLens String) String


update ∷ ∀ eff. Model -> Action -> App.Transition (Affect eff) Model Action
update model = case _ of
  Noop ->
    App.purely model
  SetRoute route ->
    App.purely model {route = route}
  UpdateIdentity {id} ->
    App.purely $ model { whoami = Just id }
  UpdateFlume json ->
    App.purely $ case model.flume, decodeFlumeDb json of
      FlumeFailure _, _ -> model
      _, Just db -> model { flume = FlumeDb db }
      FlumeUnloaded, Nothing -> model { flume = FlumeFailure "Flume index not intitialized"}
      FlumeDb flume, Nothing ->
        let mapped = mapFn json
        in if mapped == jsonNull
          then model
          else model { flume = FlumeDb $ reduceFn flume mapped }
  UpdateFriends json ->
    case decodeJson json :: Either String AboutMessage of
      Left reason -> {model, effects: lift $ Aff.log reason *> Aff.log (show json) *> pure Noop}
      Right (AboutMessage {content}) ->
        let
          name = case content.name of
            "" -> Nothing
            a -> Just a
          key = content.about
          user = { name, key }
        in purely $ model
            { userKeys = M.insert key user model.userKeys
            , userNames = maybe model.userNames (\n -> M.insert n user model.userNames) name
            }
  -- UpdateScratch event f ->
  --   let val = target node
  --   in purely $ model { scratchOffer = f model.scratchOffer }

  Publish msg ->
    { model, effects: lift $ runEffect (publish msg) }

  CreateOffer payload ->
    let msg = OfferMatch payload
    in { model, effects: lift $ runEffect (publish msg)}
  -- DeclineOffer payload ->
  --   let msg = DeclineMatch payload
  --   in { model, effects: lift $ runEffect (publish msg)}
  SetDevIdentity ident ->
    { model: model { devIdentity = Just ident }
    , effects: lift $ runEffect (E.GetIdentity (Just ident) UpdateIdentity)
    }

  ManageTenukiGame (IndexedMatch {offerPayload, moves}) ref -> case ref of
    Created el ->
      let effects = lift $ liftEff $ SetTenukiGame <$> Just <$> do
            game <- Tenuki.createGame el offerPayload.terms
            let steps = moves <#> (_.move <<< unwrap)
            setGameState game steps
            pure game
      in {model, effects}
    Removed el ->
      {model, effects: lift $ pure $ SetTenukiGame Nothing }

  SubmitKibitz move -> maybe (purely model) id $ do
    el <- fromElement =<< M.lookup "kibitzInput" model.refs
    let pub = do
          text :: String <- liftEff $ value el
          liftEff $ setValue "" el
          runEffect $ publish $ Kibitz {move, text}
    pure { model: model { kibitzDraft = "" }
          , effects: lift pub
          }
  -- case M.lookup "kibitzInput" model.refs of
  --   Nothing -> purely model
  --   Just (el :: Element) ->
  --     let
  --       pub = do
  --         text :: String <- liftEff $  el
  --         runEffect $ publish $ Kibitz {move, text}
  --     in
  --       { model: model { kibitzDraft = "" }
  --       , effects: lift pub
  --       }

  SetTenukiGame game -> purely $ model { tenukiGame = game }

  ManageRef key ref -> case ref of
    Created el -> purely $ model { refs = M.insert key el model.refs}
    Removed el -> purely $ model { refs = M.delete key model.refs}

  UpdateModel f ->
    purely $ f model

  UpdateField' f val ->
    let
      effect = liftEff do
        case (f val) of
          -- Left err -> preventDefault event *> traceA err *> pure Noop
          Left err -> traceA err *> (pure $ UpdateModel (set (O.scratchOffer <<< O.errorMsg) $ Just err))
          Right f -> traceA "OK" *> pure $ UpdateModel f
    in { model, effects: lift effect}


  HandlePlayerAutocomplete lens val ->
    purely model

  where
    publish msg = E.Publish model.devIdentity msg Noop
