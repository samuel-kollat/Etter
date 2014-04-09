module Lex( lexer, whiteSpace ) where

import System.Environment( getArgs )
import System.IO

import Text.ParserCombinators.Parsec
import qualified Text.ParserCombinators.Parsec.Token as P
import Text.ParserCombinators.Parsec.Expr
import Text.ParserCombinators.Parsec.Language

-- Lexikalna analyza
aelDef = emptyDef
    { commentStart   = "/*"
    , commentEnd     = "*/"
    , commentLine    = "//"
    , nestedComments = False
    , identStart     = letter <|> char '_'
    , identLetter    = alphaNum <|> char '_'
    , opStart        = oneOf "=+*-!><"
    , opLetter       = opStart aelDef
    , reservedOpNames= [ "=", "+", "*", "-", "/", "==", "!=", "<", "<=", ">=", ">" ]
    , reservedNames  = [ "double", "else", "if", "int", "print", "scan", "string", "while" ]
    , caseSensitive  = True
    }

-- Lexikalny analyzator
lexer = P.makeTokenParser aelDef

-- Pomocne funkcie lexikalnej analyzy
whiteSpace= P.whiteSpace lexer
integer   = P.integer lexer
double    = P.float lexer
stringLit = P.stringLiteral lexer
parens    = P.parens lexer
braces    = P.braces lexer
semi      = P.semi lexer
identifier= P.identifier lexer
reserved  = P.reserved lexer
reservedOp= P.reservedOp lexer
comma     = P.comma lexer

-- Definicia hodnot
data Value = 
      ValInt Int
    | ValDouble Double
    | ValString String
    deriving (Show, Eq, Ord)

-- Definicia vyrazov
data Expr =
    Const Value
  | Var String
  | Fun String [Arg]
  | Add Expr Expr
  | Sub Expr Expr
  | Mult Expr Expr
  | Div Expr Expr
  | Gt Expr Expr
  | GtEq Expr Expr
  | Lt Expr Expr
  | LtEq Expr Expr
  | Eq Expr Expr
  | Neq Expr Expr
  deriving (Show, Eq)

-- Ziskanie typu premennej, funkcie
getType = do
        reserved "int"
        return Int
    <|> do
        reserved "double"
        return Double
    <|> do
        reserved "string"
        return String

-- Ziskanie paramatrov funkcie pri jej deklaracii, definicii
getParams = do
        t <- getType
        i <- identifier
        comma
        p <- getParams
        return $ (Param t i):p
    <|> do
        t <- getType
        i <- identifier
        return $ [(Param t i)]
    <|> do
        return []

-- Ziskanie argumentov funkcie pri jej volani
getFuncArgs = do
        e <- expr
        comma
        a <- getFuncArgs
        return $ (Arg e):a
    <|> do
        e <- expr
        return $ [(Arg e)]
    <|> do
        return []

-- Precedencna analyza vyrazov
expr = buildExpressionParser operators term where
  operators = [
      [ op "*" Mult, op "/" Div ],
      [ op "+" Add, op "-" Sub ],
      [ op "<" Lt, op "<=" LtEq, op ">" Gt, op ">=" GtEq, op "==" Eq, op "!=" Neq]
    ]
  op name fun =
    Infix ( do { reservedOp name; return fun } ) AssocLeft

-- Spracovanie vyrazu pomocou definovanych datovych typov
term = do
    i <- integer
    return $ Const $ ValInt $ fromInteger i
  <|> do
    f <- double
    return $ Const $ ValDouble f
  <|> do
    s <- stringLit
    return $ Const $ ValString s
  <|> do
    f <- identifier
    a <- parens $ getFuncArgs
    return $ Fun f a
  <|> do
    v <- identifier
    return $ Var v
  <|> parens expr
  <?> "term"

-- Definicia struktury prikazov jazyka
data Cmd =
      Empty                             -- prazdny prikaz
    | IfStmt Expr Cmd Cmd               -- if
    | WhileStmt Expr Cmd                -- while
    | Func Type String [Param] Cmd      -- definicia funkcie
    | FuncDecl Type String [Param]      -- deklaracia funkcie (bez tela)
    | FuncCall String [Arg]             -- volanie funkcie
    | AssignStmt String Expr            -- priradenie premennej
    | VarDefStmt Type String            -- deklaracia premennej v bloku
    | ReturnStmt Expr                   -- navrat z funkcie
    | Print Expr                        -- vstavana funkcia Print
    | Scan String                       -- vstavana funkcia Scan
    | Seq [Cmd]                         -- zlozeny prikaz
    deriving (Show, Eq)

-- Datove typy v jazyku
data Type =
      String
    | Int
    | Double    
    deriving (Show, Eq)

-- Struktura parametrov funkcie
data Param = Param Type String
    deriving (Show, Eq)

-- Struktura argumentov predavanych do funkcie
data Arg = Arg Expr
    deriving (Show, Eq)

-- Syntakticka analyza
command =
    do
        semi
        return Empty
    -- (3.2)
    <|> do                              -- typ id ;
        t <- getType
        i <- identifier
        semi
        return $ VarDefStmt t i
    -- (3.3)
    <|> do                              -- return_type id ( params_list ) ;
        t <- getType
        i <- identifier
        params <- parens $ getParams
        semi
        return $ FuncDecl t i params
    -- (3.3)
    <|> do                              -- return_type id ( params_list ) { command_list }
        t <- getType
        i <- identifier
        params <- parens $ getParams
        c <- command
        return $ Func t i params c
    -- (5)
    <|> do                              -- id ( args_list ) ;
        i <- identifier
        a <- parens $ getFuncArgs
        semi
        return $ FuncCall i a
    -- (4)
    <|> do                              -- return expr ;
        reserved "return"
        e <- expr
        semi
        return $ ReturnStmt e
    <|> do                              -- print ( expr ) ;
        reserved "print"
        e <- parens $ expr
        semi
        return $ Print e
    <|> do                              -- scan ( expr ) ;
        reserved "scan"
        i <- identifier
        semi
        return $ Scan i
    <|> do                              -- id = expr ;
        i <- identifier
        reservedOp "="
        e <- expr
        semi
        return $ AssignStmt i e
    <|> do                              -- if ( expr ) { command_list } else { command_list }
        reserved "if"
        b <- parens $ expr
        c1 <- command
        reserved "else"
        c2 <- command
        return $ IfStmt b c1 c2
    <|> do                              -- while ( expr ) { command_list }
        reserved "while"
        b <- parens $ expr
        c <- command
        return $ WhileStmt b c
    <|> do                              -- { command_list }
        seq <- braces $ many command
        return $ Seq seq
    <?> "command"

-- Tabulka premennych
type VarTable = [(String, Value)]

setVar :: VarTable -> String -> Value -> VarTable
setVar [] var val = [(var, val)]
setVar (s@(v,vT):ss) var val =
    if v == var
        then typeCorrect vT val 
        else s : setVar ss var val
    where -- overovanie typov pri priradeni hodnoty do premennej.
        typeCorrect (ValInt i1) (ValInt i2) = (var, val):ss
        typeCorrect (ValDouble i1) (ValInt i2) = (var, ValDouble $ fromIntegral i2):ss
        typeCorrect (ValDouble i1) (ValDouble i2) = (var, val):ss
        typeCorrect (ValString i1) (ValString i2) = (var, val):ss
        typeCorrect _ _ = error $ "Type missmatch in setting variable :" ++ var 
            

getVar :: VarTable -> String -> Value
getVar [] v = error $ "Variable not found in symbol table: " ++ v
getVar (s@(var, val):ss) v =
    if v == var
        then val
        else getVar ss v
        
isVar :: VarTable -> String -> Bool
isVar [] n = False
isVar ((name, val):vs) n
    | name == n = True
    | otherwise = isVar vs n
        
-- Tabulka funkcii
data FuncRecord =   FuncRecord
                    { funcName      :: String
                    , funcType      :: Type
                    , funcParams    :: [Param]
                    , funcCommands  :: Cmd
                    } deriving Show

type FuncTable = [FuncRecord]
    
setFunc :: FuncTable -> String -> Type -> [Param] -> Cmd -> FuncTable
setFunc [] n t ps c = [FuncRecord {funcName=n, funcType=t, funcParams=ps, funcCommands=c}]
setFunc ft@(f:fs) n t ps c
    | funcName f == n = updateFunc f t ps c
    | otherwise = f : setFunc fs n t ps c
    where
        updateFunc f t ps c = 
            if funcType f == t
            then
                if funcParams f == ps
                then
                    if funcCommands f == Empty
                    then
                        if c /= Empty
                        then
                            FuncRecord {funcName=n, funcType=t, funcParams=ps, funcCommands=c} : fs
                        else
                          error $ "Multiple declarations of function: " ++ funcName f  
                    else
                      error $ "Multiple definitions of function: " ++ funcName f  
                else
                  error $ "Multiple declarations of function with different parameters: " ++ funcName f  
            else
                error $ "Multiple declarations of function with different types: " ++ funcName f

getFuncType :: FuncTable -> String -> Type
getFuncType [] fName = error $ "Cannot access type of function: " ++ fName
getFuncType (f:fs) fName
    | funcName f == fName = funcType f
    | otherwise = getFuncType fs fName

getFuncResult :: SymTable -> FuncTable -> String -> [Arg] -> SymTable
getFuncResult _ [] fName _ = error $ "Undefined function call: " ++ fName
getFuncResult st@(gt, ft, lt, gc) (f:fs) fName fArgs
    | funcName f == fName = (gt, ft, (assignArgsToParams st [] fName (funcParams f) fArgs), gc)    -- TODO: call interpret
    | otherwise = getFuncResult st fs fName fArgs

assignArgsToParams :: SymTable -> VarTable -> String -> [Param] -> [Arg] -> VarTable
assignArgsToParams _ vt _ [] [] = vt
assignArgsToParams _ _ n (p:ps) [] = error $ "Function called with less arguments than required: " ++ n
assignArgsToParams _ _ n [] (arg:args) = error $ "Function called with more arguments than required: " ++ n
assignArgsToParams st vt n ((Param pType pName):ps) ((Arg ex):args) =
    case (pType, (eval st ex)) of
        (Int, ValInt val)       -> assignArgsToParams st (setVar vt pName $ ValInt val) n ps args
        (Double, ValInt val)    -> assignArgsToParams st (setVar vt pName $ ValDouble $ fromIntegral val) n ps args
        (Double, ValDouble val) -> assignArgsToParams st (setVar vt pName $ ValDouble val) n ps args
        (String, ValString val) -> assignArgsToParams st (setVar vt pName $ ValString val) n ps args
        _   -> error $ "Passing parameter of incompatible type to a function: " ++ n

-- Tabulka symbol
type SymTable = (VarTable, FuncTable, VarTable, Bool)   -- Globalne premenne, Funkcie, Lokalne premenne, [Globalny kontext == True, Lokalny kontext == false]

getSym :: SymTable -> String -> Value
getSym  (gt, ft, lt, gc) name
    | isLocal name = getVar lt name
    | otherwise = getVar gt name
    where
        isLocal n = isVar lt n

addSym :: SymTable -> String -> Value -> SymTable
addSym (gt, ft, lt, gc) vName val
    | gc == True && not (isVar gt vName) = (setImplicitSym gt, ft, lt, gc)
    | gc == False && not (isVar lt vName) = (gt, ft, setImplicitSym lt, gc)
    | otherwise = error $ "Multiple declarations of variable: " ++ vName
    where
        setImplicitSym t  = setVar t vName val

setSym :: SymTable -> String -> Value -> SymTable
setSym (gt, ft, lt, gc) vName val
    | gc == False && (isVar lt vName) = (gt, ft, newVt lt, gc)
    | isVar gt vName = (newVt gt, ft, lt, gc)
    | otherwise = error $ "Cannot assign to non-existing variable: " ++ vName
    where
        newVt t = setVar t vName val

getFun :: SymTable -> String -> [Arg] -> SymTable
getFun st@(gt, ft, lt, gc) n args = getFuncResult st ft n args

setFun :: SymTable -> String -> Type -> [Param] -> Cmd -> SymTable
setFun (gt, ft, lt, gc) n t ps c = (gt, newFt, lt, gc)
    where
        newFt = setFunc ft n t ps c
        
setGCon :: SymTable -> SymTable
setGCon (gt, ft, lt, gc) = (gt, ft, lt, True)

setLCon :: SymTable -> SymTable
setLCon (gt, ft, lt, gc) = (gt, ft, lt, False)

switchCon :: SymTable -> SymTable
switchCon (gt, ft, lt, gc) = (gt, ft, lt, not gc)

-- Vyhodnotenie vyrazov
eval :: SymTable -> Expr -> Value
eval ts (Const i) = i

eval ts (Add e1 e2) = ev (eval ts e1) (eval ts e2)
	where 
		ev (ValInt i1) (ValInt i2) = ValInt (i1 + i2)
		ev (ValInt i1) (ValDouble i2) = ValDouble (fromIntegral i1 + i2)
		ev (ValDouble i1) (ValInt i2) = ValDouble (i1 + fromIntegral i2)
		ev (ValDouble i1) (ValDouble i2) = ValDouble (i1 + i2)
		ev (ValString i1) (ValString i2) = ValString (i1 ++ i2)
		ev _ _ = error "Type missmatch in operator +"

eval ts (Sub e1 e2) = ev (eval ts e1) (eval ts e2)
	where 
		ev (ValInt i1) (ValInt i2) = ValInt (i1 - i2)
		ev (ValInt i1) (ValDouble i2) = ValDouble (fromIntegral i1 - i2)
		ev (ValDouble i1) (ValInt i2) = ValDouble (i1 - fromIntegral i2)
		ev (ValDouble i1) (ValDouble i2) = ValDouble (i1 - i2)		
		ev _ _ = error "Type missmatch in operator -"

eval ts (Mult e1 e2) = ev (eval ts e1) (eval ts e2)
	where 
		ev (ValInt i1) (ValInt i2) = ValInt (i1 * i2)
		ev (ValInt i1) (ValDouble i2) = ValDouble (fromIntegral i1 * i2)
		ev (ValDouble i1) (ValInt i2) = ValDouble (i1 * fromIntegral i2)
		ev (ValDouble i1) (ValDouble i2) = ValDouble (i1 * i2)		
		ev _ _ = error "Type missmatch in operator *"

eval ts (Div e1 e2) = ev (eval ts e1) (eval ts e2)
	where 
		ev (ValInt i1) (ValInt i2) = if (i2 == 0) then error "Division by zero!" else ValInt (i1 `quot` i2)							
		ev (ValInt i1) (ValDouble i2) = ValDouble (fromIntegral i1 / i2)
		ev (ValDouble i1) (ValInt i2) = ValDouble (i1 / fromIntegral i2)
		ev (ValDouble i1) (ValDouble i2) = ValDouble (i1 / i2)		
		ev _ _ = error "Type missmatch in operator /"

eval ts (Gt e1 e2) = ev (eval ts e1) (eval ts e2)
	where 
		ev (ValInt i1) (ValInt i2) =  if (i1 > i2) then (ValInt 1) else (ValInt 0)
		ev (ValDouble i1) (ValDouble i2) = if (i1 > i2) then (ValInt 1) else (ValInt 0)
		ev (ValString i1) (ValString i2) = if (i1 > i2) then (ValInt 1) else (ValInt 0)
		ev _ _ = error "Type missmatch in operator >"

eval ts (GtEq e1 e2) = ev (eval ts e1) (eval ts e2)
	where 
		ev (ValInt i1) (ValInt i2) =  if (i1 >= i2) then (ValInt 1) else (ValInt 0)
		ev (ValDouble i1) (ValDouble i2) = if (i1 >= i2) then (ValInt 1) else (ValInt 0)
		ev (ValString i1) (ValString i2) = if (i1 >= i2) then (ValInt 1) else (ValInt 0)
		ev _ _ = error "Type missmatch in operator >="

eval ts (Lt e1 e2) = ev (eval ts e1) (eval ts e2)
	where 
		ev (ValInt i1) (ValInt i2) =  if (i1 < i2) then (ValInt 1) else (ValInt 0)
		ev (ValDouble i1) (ValDouble i2) = if (i1 < i2) then (ValInt 1) else (ValInt 0)
		ev (ValString i1) (ValString i2) = if (i1 < i2) then (ValInt 1) else (ValInt 0)
		ev _ _ = error "Type missmatch in operator <"

eval ts (LtEq e1 e2) = ev (eval ts e1) (eval ts e2)
	where 
		ev (ValInt i1) (ValInt i2) =  if (i1 <= i2) then (ValInt 1) else (ValInt 0)
		ev (ValDouble i1) (ValDouble i2) = if (i1 <= i2) then (ValInt 1) else (ValInt 0)
		ev (ValString i1) (ValString i2) = if (i1 <= i2) then (ValInt 1) else (ValInt 0)
		ev _ _ = error "Type missmatch in operator <="

eval ts (Eq e1 e2) = ev (eval ts e1) (eval ts e2)
	where 
		ev (ValInt i1) (ValInt i2) =  if (i1 == i2) then (ValInt 1) else (ValInt 0)
		ev (ValDouble i1) (ValDouble i2) = if (i1 == i2) then (ValInt 1) else (ValInt 0)
		ev (ValString i1) (ValString i2) = if (i1 == i2) then (ValInt 1) else (ValInt 0)
		ev _ _ = error "Type missmatch in operator =="

eval ts (Neq e1 e2) = ev (eval ts e1) (eval ts e2)
	where 
		ev (ValInt i1) (ValInt i2) =  if (i1 /= i2) then (ValInt 1) else (ValInt 0)
		ev (ValDouble i1) (ValDouble i2) = if (i1 /= i2) then (ValInt 1) else (ValInt 0)
		ev (ValString i1) (ValString i2) = if (i1 /= i2) then (ValInt 1) else (ValInt 0)
		ev _ _ = error "Type missmatch in operator !="

eval ts (Var v) = getSym ts v

--eval ts (Fun name args) = getVar lt "return"
--	where  (gt, ft, lt, gc)  = getFun ts name args

eval _ _ = ValInt 0 -- TODO: implement all evaluation

-- Interpret

interpret :: SymTable -> Cmd -> IO SymTable
interpret ts (Empty) = return ts

interpret ts (VarDefStmt t varName) = case t of
        (Int) -> return $ addSym ts varName $ ValInt 0 
        (Double) -> return $ addSym ts varName $ ValDouble 0.0
        (String) -> return $ addSym ts varName $ ValString ""
        
interpret ts (AssignStmt v e) =  return $ setSym ts v $ eval ts e 

interpret ts (Print e) = do 
    case eval ts e of
        (ValInt i) -> putStrLn $ show i
        (ValDouble d) -> putStrLn $ show d
        (ValString s) -> putStrLn s
    return ts

interpret ts (Scan var) = do 
    case getSym ts var of         
        (ValInt i) -> do
            readVal <- readLn :: IO Int  
            return $ setSym ts var $ ValInt readVal
        (ValDouble d) -> do
            readVal <- readLn :: IO Double  
            return $ setSym ts var $ ValDouble readVal
        (ValString s) -> do
            readVal <- getLine  
            return $ setSym ts var $ ValString readVal

interpret ts (IfStmt cond cmdTrue cmdFalse) = do
    case eval ts cond of
        (ValInt i) -> if i == 0 
            then do
                interpret ts cmdTrue
            else do
                interpret ts cmdFalse
        _ -> error "Condition is not an integer!"

interpret ts (WhileStmt cond cmd) = do
    case eval ts cond of
        (ValInt i) -> if i /= 0
            then do
                ts' <- interpret ts cmd
                interpret ts' $ WhileStmt cond cmd
            else do
                return ts

interpret ts (Seq []) = return ts
interpret ts (Seq (c:cs)) = do
    ts' <- interpret ts c
    interpret ts' $ Seq cs

interpret ts (FuncDecl retType funcName params) = return $ setFun ts funcName retType params Empty

interpret ts (Func retType "main" params cmd) = 
    if (retType == Int && params == []) then do
            let ts' = setLCon ts
            interpret ts' cmd
        else do
            error "Main has bad return type or has some parameters!"

interpret ts (Func retType funcName params cmd) =   
    return $ setFun ts funcName retType params cmd

--interpret ts (ReturnStmt e) = 
  --  addSym ""

--end Lex.hs
