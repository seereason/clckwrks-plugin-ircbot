{-# LANGUAGE DeriveDataTypeable, GeneralizedNewtypeDeriving, TemplateHaskell, TypeFamilies, OverloadedStrings #-}
module Clckwrks.IrcBot.Types
    ( IrcConfig(..)
    , User(..)
    , emptyIrcConfig
    ) where

import Data.ByteString.Char8 (pack)
import Data.Data             (Data, Typeable)
import Data.Word             (Word16)
import Data.IxSet            (Indexable(..), ixSet, ixFun)
import Data.SafeCopy         (Migrate(..), SafeCopy, base, deriveSafeCopy, extension)
import Data.Set              (Set, empty)
import Data.Text             (Text)
import Network.IRC.Bot.Types (User(..))
import Web.Routes            (PathInfo(..))

data User_0 = User_0
    { username_0   :: String    -- ^ username on client system
    , hostname_0   :: String  -- ^ hostname of client system
    , servername_0 :: String  -- ^ irc server client is connected to
    , realname_0   :: String    -- ^ client's real name
    }
    deriving (Data, Typeable, Eq, Ord, Read, Show)
$(deriveSafeCopy 0 'base ''User_0)

$(deriveSafeCopy 1 'extension ''User)

instance Migrate User where
    type MigrateFrom User = User_0
    migrate (User_0 un hs sn rn) =
        (User (pack un) hs sn (pack rn))

data IrcConfig_0 = IrcConfig_0
    { ircHost_0          :: String
    , ircPort_0          :: Word16
    , ircNick_0          :: String
    , ircCommandPrefix_0 :: String
    , ircUser_0          :: User
    , ircChannels_0      :: Set String
    }
    deriving (Eq, Ord, Read, Show, Data, Typeable)
$(deriveSafeCopy 0 'base ''IrcConfig_0)

data IrcConfig = IrcConfig
    { ircHost          :: String     -- ^ IRC server
    , ircPort          :: Word16     -- ^ port (usually 6667)
    , ircNick          :: String     -- ^ irc nick
    , ircCommandPrefix :: String     -- ^ prefix for bot commands
    , ircUser          :: User       -- ^ irc 'User'
    , ircChannels      :: Set String -- ^ channels to join on connect
    , ircEnabled       :: Bool       -- ^ enable the bot
    }
    deriving (Eq, Ord, Read, Show, Data, Typeable)
$(deriveSafeCopy 1 'extension ''IrcConfig)

instance Migrate IrcConfig where
    type MigrateFrom IrcConfig = IrcConfig_0
    migrate (IrcConfig_0 h p n cp u cs) = (IrcConfig h p n cp u cs True)

emptyIrcConfig :: IrcConfig
emptyIrcConfig = IrcConfig
    { ircHost          = ""
    , ircPort          = 0
    , ircNick          = ""
    , ircCommandPrefix = ""
    , ircUser          = User "" "" "" ""
    , ircChannels      = Data.Set.empty
    , ircEnabled       = False
    }
