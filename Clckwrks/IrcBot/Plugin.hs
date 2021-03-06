{-# LANGUAGE RecordWildCards, FlexibleContexts, OverloadedStrings #-}
module Clckwrks.IrcBot.Plugin where

import Clckwrks
import Clckwrks.Monad                (ClckPluginsSt)
import Clckwrks.Plugin               (clckPlugin)
import Clckwrks.IrcBot.URL           (IrcBotURL(..), IrcBotAdminURL(..))
import Clckwrks.IrcBot.Acid          (GetIrcConfig(..), initialIrcBotState)
import Clckwrks.IrcBot.Monad         (IrcBotConfig(..), runIrcBotT)
import Clckwrks.IrcBot.Route         (routeIrcBot)
import Clckwrks.IrcBot.Types         (IrcConfig(..), emptyIrcConfig)
import Control.Concurrent            (ThreadId, killThread)
import Control.Monad.State           (get)
import Data.Acid                     as Acid
import Data.Acid.Local               (createCheckpointAndClose, openLocalStateFrom)
import Data.ByteString               (ByteString)
import Data.ByteString.Char8         as C
import Data.Text                     (Text)
import qualified Data.Text.Lazy      as TL
import Data.Maybe                    (fromMaybe)
import Data.Set                      (Set)
import qualified Data.Set            as Set
import Network                       (PortID(PortNumber))
import Network.IRC.Bot.BotMonad      (BotMonad(..))
import Network.IRC.Bot.Core          as IRC (BotConf(..), User(..), nullBotConf, simpleBot)
import Network.IRC.Bot.Log           (LogLevel(..), nullLogger, stdoutLogger)
import Network.IRC.Bot.Part.Dice     (dicePart)
import Network.IRC.Bot.Part.Hello    (helloPart)
import Network.IRC.Bot.Part.Ping     (pingPart)
import Network.IRC.Bot.Part.NickUser (nickUserPart)
import Network.IRC.Bot.Part.Channels (initChannelsPart)
import Network.IRC.Bot.PosixLogger   (posixLogger)
import System.FilePath               ((</>))
import Web.Plugins.Core              (Plugin(..), Plugins(..), When(..), addCleanup, addHandler, initPlugin, getConfig, getPluginRouteFn)
import Paths_clckwrks_plugin_ircbot  (getDataDir)

ircBotHandler :: (IrcBotURL -> [(Text, Maybe Text)] -> Text)
              -> IrcBotConfig
              -> ClckPlugins
              -> [Text]
              -> ClckT ClckURL (ServerPartT IO) Response
ircBotHandler showIrcBotURL ircBotConfig plugins paths =
    case parseSegments fromPathSegments paths of
      (Left e)  -> notFound $ toResponse (show e)
      (Right u) ->
          ClckT $ withRouteT flattenURL $ unClckT $ runIrcBotT ircBotConfig $ routeIrcBot u
    where
      flattenURL ::   ((url' -> [(Text, Maybe Text)] -> Text) -> (IrcBotURL -> [(Text, Maybe Text)] -> Text))
      flattenURL _ u p = showIrcBotURL u p

ircBotInit :: ClckPlugins
           -> IO (Maybe Text)
ircBotInit plugins =
    do (Just ircBotShowFn) <- getPluginRouteFn plugins (pluginName ircBotPlugin)
       (Just clckShowFn) <- getPluginRouteFn plugins (pluginName clckPlugin)
       mTopDir <- clckTopDir <$> getConfig plugins
       let basePath  = maybe "_state"   (\td -> td </> "_state")   mTopDir -- FIXME
           ircLogDir = maybe "_irclogs" (\td -> td </> "_irclogs") mTopDir
       acid <- openLocalStateFrom (basePath </> "ircBot") (initialIrcBotState emptyIrcConfig)
       addCleanup plugins Always (createCheckpointAndClose acid)
       reconnect <- botConnect plugins acid ircLogDir
       let ircBotConfig = IrcBotConfig { ircBotLogDirectory = ircLogDir
                                       , ircBotState        = acid
                                       , ircBotClckURL      = clckShowFn
                                       , ircReconnect       = reconnect
                                       }

--       addPreProc plugins (ircBotCmd ircBotShowFn)
       addHandler plugins (pluginName ircBotPlugin) (ircBotHandler ircBotShowFn ircBotConfig)
       addNavBarCallback plugins (ircBotNavBarCallback ircBotShowFn)
       return Nothing

ircBotNavBarCallback :: (IrcBotURL -> [(Text, Maybe Text)] -> Text)
                   -> ClckT ClckURL IO (String, [NamedLink])
ircBotNavBarCallback ircBotShowURL =
    return ("Irc Bot", [(NamedLink "IRC logs" (ircBotShowURL IrcLogs []))])

botConnect :: Plugins theme n hook config st
           -> Acid.AcidState (Acid.EventState GetIrcConfig)
           -> FilePath
           -> IO (IO ())
botConnect plugins ircBot ircBotLogDir =
    do ic@IrcConfig{..} <- Acid.query ircBot GetIrcConfig
       if ircEnabled
          then do let botConf = nullBotConf { channelLogger = Just $ posixLogger (Just ircBotLogDir) "#happs"
                                            , IRC.host      = ircHost
                                            , IRC.port      = PortNumber $ fromIntegral ircPort
                                            , nick          = C.pack $ ircNick
                                            , commandPrefix = ircCommandPrefix
                                            , user          = ircUser
                                            , channels      = Set.map C.pack ircChannels
                                            , limits        = Just (5, 2000000)
                                            }
                  ircParts <- initParts (channels botConf)
                  (tids, reconnect) <- simpleBot botConf ircParts
                  addCleanup plugins Always (mapM_ killThread tids)
                  return reconnect
          else return (return ())

initParts :: (BotMonad m) =>
             Set ByteString  -- ^ set of channels to join
          -> IO [m ()]
initParts chans =
    do (_, channelsPart) <- initChannelsPart chans
       return [ pingPart
              , nickUserPart
              , channelsPart
              , dicePart
              , helloPart
              ]

addIrcBotAdminMenu :: ClckT url IO ()
addIrcBotAdminMenu =
    do p <- plugins <$> get
       (Just showIrcBotURL) <- getPluginRouteFn p (pluginName ircBotPlugin)
       let reconnectURL = showIrcBotURL (IrcBotAdmin IrcBotReconnect) []
           settingsURL  = showIrcBotURL (IrcBotAdmin IrcBotSettings) []
       addAdminMenu ("IrcBot", [ (Set.fromList [Administrator, Editor], "Reconnect", reconnectURL)
                               , (Set.fromList [Administrator, Editor], "Settings" , settingsURL)
                               ])

ircBotPlugin :: Plugin IrcBotURL Theme (ClckT ClckURL (ServerPartT IO) Response) (ClckT ClckURL IO ()) ClckwrksConfig ClckPluginsSt
ircBotPlugin = Plugin
    { pluginName       = "ircBot"
    , pluginInit       = ircBotInit
    , pluginDepends    = []
    , pluginToPathInfo = toPathInfo
    , pluginPostHook   = addIrcBotAdminMenu
    }

plugin :: ClckPlugins -- ^ plugins
       -> Text        -- ^ baseURI
       -> IO (Maybe Text)
plugin plugins baseURI =
    initPlugin plugins baseURI ircBotPlugin
