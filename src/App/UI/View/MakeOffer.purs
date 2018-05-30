module App.UI.View.MakeOffer where

import Prelude

import App.IgoMsg (StoneColor(..))
import App.UI.Action (Action(..))
import App.UI.Model (Model, User, EzModel)
import App.UI.Optics (ModelLens, opponent, scratchOffer)
import App.UI.Optics as O
import App.Utils (maybeToEither)
import DOM.Classy.Event (toEvent)
import Data.Argonaut (toNumber)
import Data.Argonaut as Json
import Data.Bifunctor (rmap)
import Data.Either (Either(..))
import Data.Int (fromString)
import Data.Lens (over, set, (%~), (.~), (^.))
import Data.Maybe (Maybe(..), maybe)
import Data.Number as Number
import Data.StrMap as M
import Data.String (Pattern(..))
import Data.String as String
import Debug.Trace (traceA, traceAny)
import Spork.Html (classes)
import Spork.Html as H

div_ k = H.div [classes [k]]

playersForm :: Model -> EzModel -> H.Html Action
playersForm model@{scratchOffer} {whoami} =
  div_ "players-form"
    [ H.button [classes ["switcher"], H.onClick switchEvent] [H.text "switch"]
    , div_ "players"
      [ div_ "player"
        [ H.label [] [H.text "Black: "]
        , black
        ]
      , div_ "player"
        [ H.label [] [H.text "White: "]
        , white
        ]
      ]
    ]
  where
    {opponent, myColor} = scratchOffer
    userName = case _ of
      Right {key, name} -> maybe key id name
      Left name -> name
    opponentName = userName opponent
    oppRef = "scratchOpponentField"
    opponentLens :: ModelLens (Either String User)
    opponentLens = O.scratchOffer <<< O.opponent

    swapColor :: Model -> Model
    swapColor = O.scratchOffer <<< O.myColor %~ case _ of
      Black -> White
      White -> Black

    updateOpponent :: String -> (Model -> Model)
    updateOpponent name = opponentLens .~ Left name

    displayUser :: User -> String
    displayUser user = case user.name of
      Just name -> name <> " (" <> user.key <> ")"
      Nothing -> user.key

    containsPrefix = String.contains $ Pattern $ opponentName
    names = M.values $ M.filterKeys containsPrefix model.userNames
    handler = \v -> Just $ UpdateModel $ updateOpponent v
    refh = Just <<< ManageRef oppRef
    suggestions = names
    displaySuggestion user = H.li [] [H.text $ displayUser user]
      where name = maybe
    opponentField =
      H.div []
        [ H.input [H.value opponentName, H.onValueInput handler, H.ref refh]
        , H.ul [] $ map displaySuggestion suggestions
        ]
    switchEvent = H.always $ const $ UpdateModel swapColor
    meField = H.text "mijkl"
    {white, black} = case myColor of
      White -> {white: meField, black: opponentField}
      Black -> {black: meField, white: opponentField}


gameTermsForm :: Model -> H.Html Action
gameTermsForm {scratchOffer} =
  H.div []
    [ sizeForm
    , handicapForm
    , komiForm
    ]
  where
    {terms} = scratchOffer
    sizeLens = O.scratchOffer <<< O.terms <<< O.size
    komiLens = O.scratchOffer <<< O.terms <<< O.komi
    handicapLens = O.scratchOffer <<< O.terms <<< O.handicap
    updateSize = \s -> UpdateModel <$> set sizeLens <$> fromString s
    updateKomi = \s -> UpdateModel <$> set komiLens <$> (Number.fromString s)
    updateHandicap = \s -> UpdateModel <$> set handicapLens <$> fromString s

    sizeForm =
      H.div [classes ["control-group"]]
        [ H.label [] [H.text "Size"]
        , H.input [H.value $ show terms.size, H.type_ H.InputNumber, H.onValueInput updateSize]
        , H.text " x "
        , H.text "19"
        ]

    handicapForm =
      H.div [classes ["control-group"]]
        [ H.label [] [H.text "Handicap"]
        , H.input [H.value $ show terms.handicap, H.type_ H.InputNumber, H.onValueInput updateHandicap]
        ]

    komiForm =
      H.div [classes ["control-group"]]
        [ H.label [] [H.text "Komi"]
        , H.input [H.value $ show terms.komi, H.type_ H.InputNumber, H.onValueInput updateKomi]
        -- , H.input [H.value $ show terms.komi, H.onValueChange $ \val -> UpdateModel <$> (set komiLens) <$> (toNumber $ Json.fromString val)]
        ]

offerForm :: Model -> EzModel -> H.Html Action
offerForm model ez =
  H.section []
    [ H.form []
      [ H.lazy2 playersForm model ez
      , H.lazy  gameTermsForm model
      ]
    ]
