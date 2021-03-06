module App.UI.View.Game where

import Prelude

import App.Common (div_)
import App.Flume (IndexedMatch(IndexedMatch), KibitzStep(KibitzStep), assignColors, isMatchEnd, lastMoveKey, matchKey, moveNumber, myColor, nextMover)
import App.IgoMsg (IgoMove(..), IgoMsg(PlayMove))
import App.UI.Action (Action(..))
import App.UI.Model (EzModel, Model, userNameFromKey)
import App.UI.Optics as O
import App.UI.Routes (Route(..))
import App.UI.View.Components (link)
import DOM.Event.KeyboardEvent as KeyboardEvent
import Data.Array (length)
import Data.Lens as Lens
import Data.Maybe (Maybe(..), maybe)
import Data.StrMap as M
import Spork.Html as H
import Tenuki.Game as Tenuki


viewGame :: Model -> EzModel -> Maybe IndexedMatch -> H.Html Action
viewGame model@{tenukiClient} ez@{db, whoami} maybeMatch = case maybeMatch of
  Just match@(IndexedMatch {offerPayload, moves}) ->
    let
      {terms} = offerPayload
      gameDiv = H.div
        [ H.classes ["tenuki-board"]
        , H.ref (Just <<< (ManageTenukiGame match)) ]
        []
      datum k v =
        H.div [H.classes $ ["datum", k]]
          [ div_ "key" [H.text k]
          , div_ "val" [H.text v]
          ]
      gameState = (Tenuki.currentState <<< Tenuki.getGame) <$> tenukiClient
      blackCaps = maybe 0 _.blackStonesCaptured gameState
      whiteCaps = maybe 0 _.whiteStonesCaptured gameState
      {white, black} = assignColors match
      turnKey = nextMover db match
      playerClasses key = H.classes
        if turnKey /= key
        then ["player"]
        else if key == whoami
        then ["player", "my-turn"]
        else ["player", "their-turn"]
      blackPlayer = H.div [playerClasses black]
        [ div_ "turn-notification" [H.text "your turn"]
        , div_ "name" [H.text $ userNameFromKey model black]
        , div_ "caps" [H.text $ "captures: " <> show whiteCaps]
        ]
      whitePlayer = H.div [playerClasses white]
        [ div_ "turn-notification" [H.text "your turn"]
        , div_ "name" [H.text $ userNameFromKey model white]
        , div_ "caps" [H.text $ "captures: " <> show blackCaps]
        ]

      moveSubmitter move = H.always_ $ Publish $ PlayMove
        { move
        , lastMove: lastMoveKey match
        , subjectiveMoveNum: -1
        }

      passButton active = H.button
        [ H.classes ["pass"]
        , H.disabled (not active)
        , H.onClick $ moveSubmitter Pass
        ]
        [ H.text "pass" ]

      resignButton = H.button
        [ H.classes ["resign"] ]
        [ H.text "resign" ]

      finalizeButton = H.button
        [ H.classes ["finalize"]
        , H.onClick $ moveSubmitter Finalize
        ]
        [ H.text "done" ]

      kibitzes = maybe [] id $ M.lookup (matchKey match) db.matchKibitzes
      kibitzPanel = kibitzes <#> \(KibitzStep {text, author}) ->
        div_ "kibitz"
          [ div_ "author" [H.text $ userNameFromKey model author]
          , div_ "message" [H.text text]
          ]
      move = lastMoveKey match
      text = model.kibitzDraft
      handleKibitzEnter ev =
        if KeyboardEvent.code ev == "Enter"
        then Just $ SubmitKibitz move
        else Nothing

      handleKibitzInput =
        Just <<< UpdateModel <<< (Lens.set O.kibitzDraft)
      handleKibitzSend =
        H.always_ $ SubmitKibitz move

      controls = div_ "controls"
        let
          active = nextMover db match == whoami
          firstButton = if isMatchEnd match
            then finalizeButton
            else passButton active
        in [ firstButton, resignButton ]

      info =
        [ datum "move" $ show $ moveNumber match
        , datum "komi" $ show terms.komi
        , datum "hand." $ show terms.handicap
        ]

    in div_ "game-content"
      [ gameDiv
      , div_ "panel"
        [ div_ "players"
          [ blackPlayer, whitePlayer]
        , div_ "game-info" $
            case myColor match whoami of
              Just _ -> [controls] <> info
              Nothing -> info
        , div_ "kibitz-container"
          [ div_ "kibitzes" kibitzPanel
          , div_ "kibitz-input"
            [ H.input
              [ H.type_ H.InputText
              , H.placeholder "Type to talk..."
              -- , H.onValueInput handleKibitzInput
              , H.onKeyPress handleKibitzEnter
              , H.ref $ Just <<< ManageRef "kibitzInput"
              ]
            , H.button
              [ H.onClick handleKibitzSend ]
              [ H.text "Chat" ]
            ]
          ]
      ]
      , link Dashboard H.a [H.classes ["close"]] [H.text "×"]
      ]
  Nothing -> H.text "NO GAME FOUND"
