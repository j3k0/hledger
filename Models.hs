
module Models -- data types & behaviours
where

import Text.Printf
import Text.Regex
import Data.List

import Utils

-- basic types

type Date = String
type Status = Bool
type Account = String

-- amounts
-- amount arithmetic currently ignores currency conversion

data Amount = Amount {
                      currency :: String,
                      quantity :: Double
                     } deriving (Eq,Ord)

instance Num Amount where
    abs (Amount c q) = Amount c (abs q)
    signum (Amount c q) = Amount c (signum q)
    fromInteger i = Amount "$" (fromInteger i)
    (+) = amountAdd
    (-) = amountSub
    (*) = amountMult
Amount ca qa `amountAdd` Amount cb qb = Amount ca (qa + qb)
Amount ca qa `amountSub` Amount cb qb = Amount ca (qa - qb)
Amount ca qa `amountMult` Amount cb qb = Amount ca (qa * qb)

instance Show Amount where show = amountRoundedOrZero

amountRoundedOrZero :: Amount -> String
amountRoundedOrZero (Amount cur qty) =
    let rounded = printf "%.2f" qty in
    case rounded of
      "0.00"    -> "0"
      "-0.00"   -> "0"
      otherwise -> cur ++ rounded

-- modifier & periodic entries

data ModifierEntry = ModifierEntry { -- aka "automated entry"
                    valueexpr :: String,
                    m_transactions :: [Transaction]
                   } deriving (Eq)

instance Show ModifierEntry where 
    show e = "= " ++ (valueexpr e) ++ "\n" ++ unlines (map show (m_transactions e))

data PeriodicEntry = PeriodicEntry {
                    periodexpr :: String,
                    p_transactions :: [Transaction]
                   } deriving (Eq)

instance Show PeriodicEntry where 
    show e = "~ " ++ (periodexpr e) ++ "\n" ++ unlines (map show (p_transactions e))

-- entries
-- a register entry is displayed as two or more lines like this:
-- date       description          account                 amount       balance
-- DDDDDDDDDD dddddddddddddddddddd aaaaaaaaaaaaaaaaaaaaaa  AAAAAAAAAAA AAAAAAAAAAAA
--                                 aaaaaaaaaaaaaaaaaaaaaa  AAAAAAAAAAA AAAAAAAAAAAA
--                                 ...                     ...         ...
-- dateWidth = 10
-- descWidth = 20
-- acctWidth = 22
-- amtWidth  = 11
-- balWidth  = 12

data Entry = Entry {
                    edate :: Date,
                    estatus :: Status,
                    ecode :: String,
                    edescription :: String,
                    etransactions :: [Transaction]
                   } deriving (Eq,Ord)

instance Show Entry where show = showEntry

showEntry e = (showDate $ edate e) ++ " " ++ (showDescription $ edescription e) ++ " "
showDate d = printf "%-10s" d
showDescription s = printf "%-20s" (elideRight 20 s)

isEntryBalanced :: Entry -> Bool
isEntryBalanced e = (sumTransactions . etransactions) e == 0

autofillEntry :: Entry -> Entry
autofillEntry e = 
    Entry (edate e) (estatus e) (ecode e) (edescription e)
              (autofillTransactions (etransactions e))

-- transactions

data Transaction = Transaction {
                                taccount :: Account,
                                tamount :: Amount
                               } deriving (Eq,Ord)

instance Show Transaction where show = showTransaction

showTransaction t = (showAccount $ taccount t) ++ "  " ++ (showAmount $ tamount t) 
showAmount amt = printf "%11s" (show amt)
showAccount s = printf "%-22s" (elideRight 22 s)

elideRight width s =
    case length s > width of
      True -> take (width - 2) s ++ ".."
      False -> s

-- elideAccountRight width abbrevlen a = 
--     case length a > width of
--       False -> a
--       True -> abbreviateAccountComponent abbrevlen a 
        
-- abbreviateAccountComponent abbrevlen a =
--     let components = splitAtElement ':' a in
--     case 
    
autofillTransactions :: [Transaction] -> [Transaction]
autofillTransactions ts =
    let (ns, as) = partition isNormal ts
            where isNormal t = (currency $ tamount t) /= "AUTO" in
    case (length as) of
      0 -> ns
      1 -> ns ++ [balanceTransaction $ head as]
          where balanceTransaction t = t{tamount = -(sumTransactions ns)}
      otherwise -> error "too many blank transactions in this entry"

sumTransactions :: [Transaction] -> Amount
sumTransactions ts = sum [tamount t | t <- ts]

-- entrytransactions
-- We parse Entries containing Transactions and flatten them into
-- (entry,transaction) pairs (entrytransactions, hereafter referred to as
-- "transactions") for easier processing. (So far, these types have
-- morphed through E->T; (T,E); ET; E<->T; (E,T)).

type EntryTransaction = (Entry,Transaction)

entry       (e,t) = e
transaction (e,t) = t
date        (e,t) = edate e
status      (e,t) = estatus e
code        (e,t) = ecode e
description (e,t) = edescription e
account     (e,t) = taccount t
amount      (e,t) = tamount t
                                         
flattenEntry :: Entry -> [EntryTransaction]
flattenEntry e = [(e,t) | t <- etransactions e]

entryTransactionsFrom :: [Entry] -> [EntryTransaction]
entryTransactionsFrom es = concat $ map flattenEntry es

matchTransactionAccount :: String -> EntryTransaction -> Bool
matchTransactionAccount s t =
    case matchRegex (mkRegex s) (account t) of
      Nothing -> False
      otherwise -> True

matchTransactionDescription :: String -> EntryTransaction -> Bool
matchTransactionDescription s t =
    case matchRegex (mkRegex s) (description t) of
      Nothing -> False
      otherwise -> True

showTransactionsWithBalances :: [EntryTransaction] -> Amount -> String
showTransactionsWithBalances [] _ = []
showTransactionsWithBalances ts b =
    unlines $ showTransactionsWithBalances' ts dummyt b
        where
          dummyt = (Entry "" False "" "" [], Transaction "" (Amount "" 0))
          showTransactionsWithBalances' [] _ _ = []
          showTransactionsWithBalances' (t:ts) tprev b =
              (if (entry t /= (entry tprev))
               then [showTransactionDescriptionAndBalance t b']
               else [showTransactionAndBalance t b'])
              ++ (showTransactionsWithBalances' ts t b')
                  where b' = b + (amount t)

showTransactionDescriptionAndBalance :: EntryTransaction -> Amount -> String
showTransactionDescriptionAndBalance t b =
    (showEntry $ entry t) ++ (showTransaction $ transaction t) ++ (showBalance b)

showTransactionAndBalance :: EntryTransaction -> Amount -> String
showTransactionAndBalance t b =
    (replicate 32 ' ') ++ (showTransaction $ transaction t) ++ (showBalance b)

showBalance b = printf " %12s" (amountRoundedOrZero b)

-- accounts

accountsFromTransactions :: [EntryTransaction] -> [Account]
accountsFromTransactions ts = nub $ map account ts

-- ["a:b:c","d:e"] -> ["a","a:b","a:b:c","d","d:e"]
expandAccounts :: [Account] -> [Account]
expandAccounts l = nub $ concat $ map expand l
                where
                  expand l' = map (concat . intersperse ":") (tail $ inits $ splitAtElement ':' l')

-- ledger

data Ledger = Ledger {
                      modifier_entries :: [ModifierEntry],
                      periodic_entries :: [PeriodicEntry],
                      entries :: [Entry]
                     } deriving (Eq)

instance Show Ledger where
    show l = "Ledger with " ++ m ++ " modifier, " ++ p ++ " periodic, " ++ e ++ " normal entries:\n"
                     ++ (concat $ map show (modifier_entries l))
                     ++ (concat $ map show (periodic_entries l))
                     ++ (concat $ map show (entries l))
                     where 
                       m = show $ length $ modifier_entries l
                       p = show $ length $ periodic_entries l
                       e = show $ length $ entries l

ledgerAccountsUsed :: Ledger -> [Account]
ledgerAccountsUsed l = accountsFromTransactions $ entryTransactionsFrom $ entries l

ledgerAccountTree :: Ledger -> [Account]
ledgerAccountTree = sort . expandAccounts . ledgerAccountsUsed

ledgerTransactions :: Ledger -> [EntryTransaction]
ledgerTransactions l = entryTransactionsFrom $ entries l

ledgerTransactionsMatching :: ([String],[String]) -> Ledger -> [EntryTransaction]
ledgerTransactionsMatching ([],[]) l = ledgerTransactionsMatching ([".*"],[".*"]) l
ledgerTransactionsMatching (rs,[]) l = ledgerTransactionsMatching (rs,[".*"]) l
ledgerTransactionsMatching ([],rs) l = ledgerTransactionsMatching ([".*"],rs) l
ledgerTransactionsMatching (acctregexps,descregexps) l =
    intersect 
    (concat [filter (matchTransactionAccount r) ts | r <- acctregexps])
    (concat [filter (matchTransactionDescription r) ts | r <- descregexps])
    where ts = ledgerTransactions l
