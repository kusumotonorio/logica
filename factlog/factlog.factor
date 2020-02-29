! Copyright (C) 2019,2020 KUSUMOTO Norio.
! See http://factorcode.org/license.txt for BSD license.
USING: accessors arrays assocs classes classes.tuple combinators
combinators.short-circuit compiler.units continuations
formatting fry io kernel lexer lists locals make math namespaces
parser prettyprint prettyprint.backend prettyprint.config
prettyprint.custom prettyprint.sections quotations sequences
sequences.deep sets splitting strings words words.symbol
vectors ;

IN: factlog

SYMBOL: !!    ! cut operator         in prolog: !
SYMBOL: __    ! anonymous variable   in prolog: _
SYMBOL: ;;    ! disjunction, or      in prolog: ;
SYMBOL: \+    ! negation             in prolog: not, \+

<PRIVATE

<<
TUPLE: logic-pred name defs ;

: <pred> ( name -- pred )
    logic-pred new
        swap >>name
        V{ } clone >>defs ;

MIXIN: LOGIC-VAR
SINGLETON: NORMAL-LOGIC-VAR
SINGLETON: ANONYMOUSE-LOGIC-VAR
INSTANCE: NORMAL-LOGIC-VAR LOGIC-VAR
INSTANCE: ANONYMOUSE-LOGIC-VAR LOGIC-VAR

: logic-var? ( obj -- ? )
    dup symbol? [ get LOGIC-VAR? ] [ drop f ] if ; inline

SYMBOLS: *trace?* *trace-depth* ;

PRIVATE>

: trace ( -- ) t *trace?* set-global ;

: notrace ( -- ) f *trace?* set-global ;

SYNTAX: LOGIC-VARS: ";"
    [
        create-word-in
        [ reset-generic ]
        [ define-symbol ]
        [ NORMAL-LOGIC-VAR swap set-global ] tri
    ] each-token ;

SYNTAX: LOGIC-PREDS: ";"
    [
        create-word-in
        [ reset-generic ]
        [ define-symbol ]
        [ [ name>> <pred> ] keep set-global ] tri
    ] each-token ;
>>

<PRIVATE

TUPLE: logic-goal pred args ;

: called-args ( args -- args' )
    [ dup callable? [ call( -- term ) ] when ] map ;

:: <goal> ( pred args -- goal )
    pred get args called-args logic-goal boa ; inline

: def>goal ( goal-def -- goal ) unclip swap <goal> ; inline

: normalize ( goal-def/defs -- goal-defs )
    dup {
        [ !! = ]
        [ ?first dup symbol? [ get logic-pred? ] [ drop f ] if ]
    } 1|| [ 1array ] when ;

TUPLE: logic-env table ;

: <env> ( -- env ) logic-env new H{ } clone >>table ; inline

:: env-put ( x pair env -- ) pair x env table>> set-at ; inline

: env-get ( x env -- pair/f ) table>> at ; inline

: env-delete ( x env -- ) table>> delete-at ; inline

: env-clear ( env -- ) table>> clear-assoc ; inline

: dereference ( term env -- term' env' )
    [ 2dup env-get [ 2nip first2 t ] [ f ] if* ] loop ;

PRIVATE>

M: logic-env at*
    dereference {
        { [ over logic-goal? ] [
            [ [ pred>> ] [ args>> ] bi ] dip at <goal> t ] }
        { [ over tuple? ] [
            '[ tuple-slots [ _ at ] map ]
            [ class-of slots>tuple ] bi t ] }
        { [ over sequence? ] [
              '[ _ at ] map t ] }
        [ drop t ]
    } cond ;

<PRIVATE

TUPLE: callback-env env trail ;

C: <callback-env> callback-env

M: callback-env at* env>> at* ;

TUPLE: cut-info cut? ;

C: <cut> cut-info

: cut? ( cut-info -- ? ) cut?>> ; inline

: set-info ( ? cut-info -- ) cut?<< ; inline

: set-info-if-f ( ? cut-info -- )
    dup cut?>> [ 2drop ] [ cut?<< ] if ; inline

DEFER: unify*

:: (unify*) ( x! x-env! y! y-env! trail tmp-env -- success? )
    f :> ret-value!  f :> ret?!  f :> ret2?!
    t :> loop?!
    [ loop? ] [
        { { [ x logic-var? ] [
                x x-env env-get :> xp!
                xp not [
                    y y-env dereference y-env! y!
                    x y = x-env y-env eq? and [
                        x { y y-env } x-env env-put
                        x-env tmp-env eq? [
                            { x x-env } trail push
                        ] unless
                    ] unless
                    f loop?!  t ret?!  t ret-value!
                ] [
                    xp first2 x-env! x!
                    x x-env dereference x-env! x!
                ] if ] }
          { [ y logic-var? ] [
                x y x! y!  x-env y-env x-env! y-env! ] }
          [ f loop?! ]
        } cond
    ] while

    ret? [
        t ret-value!
        x y [ logic-goal? ] both? [
            x pred>> y pred>> = [
                x args>> x!  y args>> y!
            ] [
                f ret-value! t ret2?!
            ] if
        ] when
        ret2? [
            {
                { [ x y [ tuple? ] both? ] [
                      x y [ class-of ] same? [
                          x y [ tuple-slots ] bi@ :> ( x-slots y-slots )
                          0 :> i!  x-slots length 1 - :> stop-i  t :> loop?!
                          [ i stop-i <= loop? and ] [
                              x-slots y-slots [ i swap nth ] bi@
                                  :> ( x-item y-item )
                              x-item x-env y-item y-env trail tmp-env unify* [
                                  f loop?!
                                  f ret-value!
                              ] unless
                              i 1 + i!
                          ] while
                      ] [ f ret-value! ] if ] }
                { [ x y [ sequence? ] both? ] [
                      x y [ class-of ] same? x y [ length ] same? and [
                          0 :> i!  x length 1 - :> stop-i  t :> loop?!
                          [ i stop-i <= loop? and ] [
                              x y [ i swap nth ] bi@ :> ( x-item y-item )
                              x-item x-env y-item y-env trail tmp-env unify* [
                                  f loop?!
                                  f ret-value!
                              ] unless
                              i 1 + i!
                          ] while
                      ] [ f ret-value! ] if ] }
                [  x y = ret-value! ]
            } cond
        ] unless
    ] unless
    ret-value ;

:: unify* ( x x-env y y-env trail tmp-env -- success? )
    *trace?* get-global :> trace?
    0 :> depth!
    trace? [
        *trace-depth* counter depth!
        depth [ "\t" printf ] times
        "Unification of " printf x-env x of pprint
        " and " printf y pprint nl
    ] when
    x x-env y y-env trail tmp-env (unify*) :> success?
    trace? [
        depth [ "\t" printf ] times
        success? [ "==> Success\n" ] [ "==> Fail\n" ] if "%s\n" printf
        *trace-depth* get-global 1 - *trace-depth* set-global
    ] when
    success? ;

: each-until ( seq quot -- ) find 2drop ; inline

:: resolve-body ( body env cut quot: ( -- ) -- )
    body empty? [
        quot call( -- )
    ] [
        body unclip :> ( rest-goals! first-goal! )
        first-goal !! = [  ! cut
            rest-goals env cut [ quot call( -- ) ] resolve-body
            t cut set-info
        ] [
            first-goal callable? [
                first-goal call( -- goal ) first-goal!
            ] when
            *trace?* get-global [
                first-goal
                [ pred>> name>> "in: { %s " printf ]
                [ args>> [ "%u " printf ] each "}\n" printf ] bi
            ] when
            <env> :> d-env!
            f <cut> :> d-cut!
            first-goal pred>> defs>> [
                first2 :> ( d-head d-body )
                first-goal d-head [ args>> length ] same? [
                    d-cut cut? cut cut? or [ t ] [
                        V{ } clone :> trail
                        first-goal env d-head d-env trail d-env unify* [
                            d-body callable? [
                                d-env trail <callback-env> d-body call( cb-env -- ? ) [
                                    rest-goals env cut [ quot call( -- ) ] resolve-body
                                ] when
                            ] [
                                d-body d-env d-cut [
                                    rest-goals env cut [ quot call( -- ) ] resolve-body
                                    cut cut? d-cut set-info-if-f
                                ] resolve-body
                            ] if
                        ] when
                        trail [ first2 env-delete ] each
                        d-env env-clear
                        f
                    ] if
                ] [ f ] if
            ] each-until
        ] if
    ] if ;

: split-body ( body -- bodies ) { ;; } split [ >array ] map ;

SYMBOL: *anonymouse-var-no*

: reset-anonymouse-var-no ( -- ) 0 *anonymouse-var-no* set-global ;

: proxy-var-for-'__' ( -- var-symbol )
    [
        *anonymouse-var-no* counter "ANON-%d_" sprintf
        "factlog.private" create-word dup dup
        define-symbol
        ANONYMOUSE-LOGIC-VAR swap set-global
    ] with-compilation-unit ;

: replace-'__' ( before -- after )
    {
        { [ dup __ = ] [ drop proxy-var-for-'__' ] }
        { [ dup sequence? ] [ [ replace-'__' ] map ] }
        { [ dup tuple? ] [
              [ tuple-slots [ replace-'__' ] map ]
              [ class-of slots>tuple ] bi ] }
        [ ]
    } cond ;

: collect-logic-vars ( seq -- vars-array )
    [ logic-var? ] deep-filter members ;

:: (resolve) ( goal-def/defs quot: ( env -- ) -- )
    goal-def/defs replace-'__' normalize [ def>goal ] map :> goals
    <env> :> env
    goals env f <cut> [ env quot call( env -- ) ] resolve-body ;

: resolve ( goal-def/defs quot: ( env -- ) -- ) (resolve) ;

: resolve* ( goal-def/defs -- ) [ drop ] resolve ;

SYMBOL: dummy-item

:: negation-goal ( goal -- negation-goal )
    "failo_" <pred> :> f-pred
    f-pred { } clone logic-goal boa :> f-goal
    V{ { f-goal [ drop f ] } } f-pred defs<<
    "trueo_" <pred> :> t-pred
    t-pred { } clone logic-goal boa :> t-goal
    V{ { t-goal [ drop t ] } } t-pred defs<<
    goal pred>> name>> "\\+%s_" sprintf <pred> :> negation-pred
    negation-pred goal args>> clone logic-goal boa :> negation-goal
    V{
        { negation-goal { goal !! f-goal } }
        { negation-goal { t-goal } }
    } negation-pred defs<<  ! \+P_ { P !! { failo_ } ;; { trueo_ } } rule
    negation-goal ;

SYMBOLS: at-the-beginning at-the-end ;

:: (rule) ( head body pos -- )
    reset-anonymouse-var-no
    head replace-'__' def>goal :> head-goal
    body replace-'__' normalize
    split-body pos at-the-beginning = [ reverse ] when  ! disjunction
    dup empty? [
        head-goal swap 2array 1vector
        head-goal pred>> [
            pos at-the-end = [ swap ] when append!
        ] change-defs drop
    ] [
        f :> negation?!
        [
            [
                {
                    { [ dup \+ = ] [ drop dummy-item t negation?! ] }
                    { [ dup array? ] [
                          def>goal negation? [ negation-goal ] when
                          f negation?! ] }
                    { [ dup callable? ] [
                          call( -- goal ) negation? [ negation-goal ] when
                          f negation?! ] }
                    { [ dup [ t = ] [ f = ] bi or ] [
                          :> t/f! negation? [ t/f not t/f! ] when
                          t/f "trueo_" "failo_" ? <pred> :> t/f-pred
                          t/f-pred { } clone logic-goal boa :> t/f-goal
                          V{ { t/f-goal [ drop t/f ] } } t/f-pred defs<<
                          t/f-goal
                          f negation?! ] }
                    { [ dup !! = ] [ f negation?! ] }  ! as '!!'
                    [ drop dummy-item f negation?! ]
                } cond
            ] map dummy-item swap remove :> body-goals
            V{ { head-goal body-goals } }
            head-goal pred>> [
                pos at-the-end = [ swap ] when append!
            ] change-defs drop
        ] each
    ] if ;

: (fact) ( head pos -- ) { } clone swap (rule) ;

PRIVATE>

: rule ( head body -- ) at-the-end (rule) ; inline

: rule* ( head body -- ) at-the-beginning (rule) ; inline

: rules ( defs -- ) [ first2 rule ] each ; inline

: fact ( head -- ) at-the-end (fact) ; inline

: fact* ( head -- ) at-the-beginning (fact) ; inline

: facts ( defs -- ) [ fact ] each ; inline

:: callback ( head quot: ( callback-env -- ? ) -- )
    head def>goal :> head-goal
    head-goal pred>> [
        { head-goal quot } suffix!
    ] change-defs drop ;

: callbacks ( defs -- ) [ first2 callback ] each ; inline

:: retract ( head-def -- )
    head-def replace-'__' def>goal :> head-goal
    head-goal pred>> defs>> :> defs
    defs [ first <env> head-goal <env> V{ } clone <env> (unify*) ] find [
        head-goal pred>> [ remove-nth! ] change-defs drop
    ] [ drop ] if ;

:: retract-all ( head-def -- )
    head-def replace-'__' def>goal :> head-goal
    head-goal pred>> defs>> :> defs
    defs [
        first <env> head-goal <env> V{ } clone <env> (unify*)
    ] reject! head-goal pred>> defs<< ;

: clear-pred ( pred -- ) get V{ } clone swap defs<< ;

:: unify ( cb-env x y -- success? )
    cb-env env>> :> env
    x env y env cb-env trail>> env (unify*) ;

:: is ( quot: ( env -- value ) dist -- goal )
    quot collect-logic-vars
    dup dist swap member? [ dist suffix ] unless :> args
    quot dist "[ %u %s is ]" sprintf <pred> :> is-pred
    is-pred args logic-goal boa :> is-goal
    V{
        {
            is-goal
            [| env | env dist env quot call( env -- value ) unify ]
        }
    } is-pred defs<<
    is-goal ;

:: =:= ( quot1: ( env -- value ) quot2: ( env -- value ) -- goal )
    quot1 quot2 [ collect-logic-vars ] bi@ union :> args
    quot1 quot2 "[ %u %u =:= ]" sprintf <pred> :> =:=-pred
    =:=-pred args logic-goal boa :> =:=-goal
    V{
        {
            =:=-goal
            [| env |
                env quot1 call( env -- value )
                env quot2 call( env -- value )
                2dup [ number? ] both? [ = ] [ 2drop f ] if ]
        }
    } =:=-pred defs<<
    =:=-goal ;

:: =\= ( quot1: ( env -- value ) quot2: ( env -- value ) -- goal )
    quot1 quot2 [ collect-logic-vars ] bi@ union :> args
    quot1 quot2 "[ %u %u =\\= ]" sprintf <pred> :> =\=-pred
    =\=-pred args logic-goal boa :> =\=-goal
    V{
        {
            =\=-goal
            [| env |
                env quot1 call( env -- value )
                env quot2 call( env -- value )
                2dup [ number? ] both? [ = not ] [ 2drop f ] if ]
        }
    } =\=-pred defs<<
    =\=-goal ;

:: assert-rule ( quot: ( env -- ) -- goal )
    quot collect-logic-vars :> args
    quot "[ %u assert-rule ]" sprintf <pred> :> assert-pred
    assert-pred args logic-goal boa :> assert-goal
    V{
        { assert-goal [| env | env quot call( env -- ) t ] }
    } assert-pred defs<<
    assert-goal ;

:: retract-rule ( quot: ( env -- ) -- goal )
    quot collect-logic-vars :> args
    quot "[ %u retract-rule ]" sprintf <pred> :> retract-pred
    retract-pred args logic-goal boa :> retract-goal
    V{
        {
            retract-goal
            [| env |
                env quot call( env -- head-goal ) retract
                t
            ]
        }
    } retract-pred defs<<
    retract-goal ;

:: retract-all-rule ( quot: ( env -- ) -- goal )
    quot collect-logic-vars :> args
    quot "[ %u retract-all-rule ]" sprintf <pred> :> retract-all-pred
    retract-all-pred args logic-goal boa :> retract-all-goal
    V{
        {
            retract-all-goal
            [| env |
                env quot call( env -- head-goal ) retract-all
                t
            ]
        }
    } retract-all-pred defs<<
    retract-all-goal ;

:: query-n ( goal-def/defs n/f -- bindings-array/success? )
    *trace?* get-global :> trace?
    0 :> n!
    f :> success?!
    V{ } clone :> bindings
    [
        goal-def/defs normalize [| env |
            env table>> keys [ get NORMAL-LOGIC-VAR? ] filter
            [ dup env at ] H{ } map>assoc
            trace? get-global [ dup [ "%u: %u\n" printf ] assoc-each ] when
            bindings push
            t success?!
            n/f [
                n 1 + n!
                n n/f >= [ return ] when
            ] when
        ] (resolve)
    ] with-return
    bindings dup {
        [ empty? ]
        [ first keys [ get NORMAL-LOGIC-VAR? ] any? not ]
    } 1|| [ drop success? ] [ >array ] if ;

: query ( goal-def/defs -- bindings-array/success? ) f query-n ;


! Built-in predicate definitions -----------------------------------------------------

LOGIC-PREDS:
    trueo failo
    varo nonvaro
    (<) (>) (>=) (=<) (==) (\==) (=) (\=)
    writeo writenlo nlo
    membero appendo lengtho listo
;

{ trueo } [ drop t ] callback

{ failo } [ drop f ] callback


<PRIVATE LOGIC-VARS: A B C X Y Z ; PRIVATE>

{ varo X } [ X of logic-var? ] callback

{ nonvaro X } [ X of logic-var? not ] callback


{ (<) X Y } [
    [ X of ] [ Y of ] bi 2dup [ number? ] both? [ < ] [ 2drop f ] if
] callback

{ (>) X Y } [
    [ X of ] [ Y of ] bi 2dup [ number? ] both? [ > ] [ 2drop f ] if
] callback

{ (>=) X Y } [
    [ X of ] [ Y of ] bi 2dup [ number? ] both? [ >= ] [ 2drop f ] if
] callback

{ (=<) X Y } [
    [ X of ] [ Y of ] bi 2dup [ number? ] both? [ <= ] [ 2drop f ] if
] callback

{ (==) X Y } [ [ X of ] [ Y of ] bi = ] callback

{ (\==) X Y } [ [ X of ] [ Y of ] bi = not ] callback

{ (=) X Y } [ dup [ X of ] [ Y of ] bi unify ] callback

{ (\=) X Y } [
    clone [ clone ] change-env [ clone ] change-trail
    dup [ X of ] [ Y of ] bi unify not
] callback


{ writeo X } [
    X of dup sequence? [
        [ dup string? [ printf ] [ pprint ] if ] each
    ] [
        dup string? [ printf ] [ pprint ] if
    ] if t
] callback

{ writenlo X } [
    X of dup sequence? [
        [ dup string? [ printf ] [ pprint ] if ] each
    ] [
        dup string? [ printf ] [ pprint ] if
    ] if nl t
] callback

{ nlo } [ drop nl t ] callback


{ membero X L{ X . Z } } fact
{ membero X L{ Y . Z } } { membero X Z } rule

{ appendo L{ } A A } fact
{ appendo L{ A . X } Y L{ A . Z } } {
    { appendo X Y Z }
} rule


<PRIVATE LOGIC-VARS: Tail N N1 ; PRIVATE>

{ lengtho L{ } 0 } fact
{ lengtho L{ __ . Tail } N } {
    { lengtho Tail N1 }
    [ [ N1 of 1 + ] N is ]
} rule


<PRIVATE LOGIC-VARS: L ; PRIVATE>

{ listo L{ } } fact
{ listo L{ __ . __ } } fact

