#lang typed/racket/base

(provide (all-defined-out))

(require )

(define-type -ρ (HashTable Symbol ⟪α⟫))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;; Stores
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(struct -σ ([m : (HashTable ⟪α⟫ (℘ -V))]
            [modified : (℘ ⟪α⟫)] ; addresses that may have been mutated
            [cardinality : (HashTable ⟪α⟫ -cardinality)]
            )
  #:transparent)
(define-type -σₖ (HashTable -αₖ (℘ -κ)))
(define-type -M (HashTable -αₖ (℘ -ΓA)))

;; Grouped mutable references to stores
(struct -Σ ([σ : -σ] [σₖ : -σₖ] [M : -M]) #:mutable #:transparent)

(define-type -cardinality (U 0 1 'N))


(struct -κ ([cont : -⟦k⟧]    ; rest of computation waiting on answer
            [pc : -Γ]       ; path-condition to use for rest of computation
            [⟪ℋ⟫ : -⟪ℋ⟫]    ; abstraction of call history
            [args : (Listof -?t)])
  #:transparent)


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;; Runtime Values
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(-V . ::= . -prim
            (-● (℘ -h))
            (-St -𝒾 (Listof ⟪α⟫))
            (-Vector (Listof ⟪α⟫))
            (-Vector^ [content : ⟪α⟫] [length : #|restricted|# -V])
            -Fn
            
            ;; Proxied higher-order values
            ;; Inlining the contract in the data definition is ok
            ;; because there's no recursion
            (-Ar [guard : -=>_] [v : ⟪α⟫] [ctx : -l³])
            (-St* [guard : -St/C] [val : ⟪α⟫] [ctx : -l³])
            (-Vector/guard [guard : (U -Vector/C -Vectorof)] [val : ⟪α⟫] [ctx : -l³])
            
            -C)

(-Fn . ::= . (-Clo -formals -⟦e⟧ -ρ -Γ)
             (-Case-Clo (Listof (Pairof (Listof Symbol) -⟦e⟧)) -ρ -Γ))

;; Contract combinators
(-C . ::= . (-And/C [flat? : Boolean]
                    [l : -⟪α⟫ℓ]
                    [r : -⟪α⟫ℓ])
            (-Or/C [flat? : Boolean]
                   [l : -⟪α⟫ℓ]
                   [r : -⟪α⟫ℓ])
            (-Not/C -⟪α⟫ℓ)
            (-One-Of/C (Setof Base))
            (-x/C [c : ⟪α⟫])
            ;; Guards for higher-order values
            -=>_
            (-St/C [flat? : Boolean]
                   [id : -𝒾]
                   [fields : (Listof -⟪α⟫ℓ)])
            (-Vectorof -⟪α⟫ℓ)
            (-Vector/C (Listof -⟪α⟫ℓ)))

;; Function contracts
(-=>_ . ::= . (-=>  [doms : (-maybe-var -⟪α⟫ℓ)] [rng : (U (Listof -⟪α⟫ℓ) 'any)] [pos : ℓ])
              (-=>i [doms : (Listof -⟪α⟫ℓ)]
                    [mk-rng : (List -Clo -λ ℓ)]
                    [pos : ℓ])
              (-Case-> (Listof (Pairof (Listof ⟪α⟫) ⟪α⟫)) [pos : ℓ]))

(struct -blm ([violator : -l]
              [origin : -l]
              [c : (Listof (U -V -v -h))]
              [v : (Listof -V)]
              [loc : ℓ]) #:transparent)
(struct -W¹ ([V : -V] [t : -?t]) #:transparent)
(struct -W ([Vs : (Listof -V)] [t : -?t]) #:transparent)
(-A . ::= . -W -blm)
(struct -ΓA ([cnd : (℘ -t)] [ans : -A]) #:transparent)

(struct -⟪α⟫ℓ ([addr : ⟪α⟫] [loc : ℓ]) #:transparent)

;; Convenient patterns
(define-match-expander -Cons
  (syntax-rules () [(_ αₕ αₜ) (-St (== -𝒾-cons) (list αₕ αₜ))])
  (syntax-rules () [(_ αₕ αₜ) (-St -𝒾-cons      (list αₕ αₜ))]))
(define-match-expander -Cons*
  (syntax-rules () [(_ α) (-St* (-St/C _ (== -𝒾-cons) _) α _)]))
(define-match-expander -Box
  (syntax-rules () [(_ α) (-St (== -𝒾-box) (list α))])
  (syntax-rules () [(_ α) (-St -𝒾-box      (list α))]))
(define-match-expander -Box*
  (syntax-rules () [(_ α) (-St* (-St/C _ (== -𝒾-box) _) α _)]))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;; Symbols and Path Conditions
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Path condition is set of terms known to have evaluated to non-#f
;; It also maintains a "canonicalized" symbolic name for each variable
(struct -Γ ([facts : (℘ -t)]
            [aliases : (HashTable Symbol -t)])
  #:transparent)

;; First order term for use in path-condition
(-t . ::= . -x
            -𝒾
            -v
            (-t.@ -h (Listof -t)))
;; Formula "head" is either a primitive operation or a stack address
(-h . ::= . -o
            -αₖ
            ;; Hacky stuff
            -One-Of/C
            (-st/c.mk -𝒾)
            (-st/c.ac -𝒾 Index)
            (-->i.mk)
            (-->i.dom Index)
            (-->i.rng)
            (-->.mk)
            (-->*.mk)
            (-->.dom Index)
            (-->.rst)
            (-->.rng)
            (-ar.mk)
            (-ar.ctc)
            (-ar.fun)
            (-values.ac Index)
            (-≥/c Base)
            (-≤/c Base)
            (->/c Base)
            (-</c Base)
            (-≡/c Base)
            (-≢/c Base)
            (-not/c -o))
(-?t . ::= . -t #f)

(-special-bin-o . ::= . '> '< '>= '<= '= 'equal? 'eqv? 'eq? #|made up|# '≢)

;; Cache for address lookup in local block
;; TODO: merge this in as part of path-condition
(define-type -$ (HashTable -t -V))

(define-match-expander -not/c/simp
  (syntax-rules ()
    [(_ p) (-not/c p)])
  (syntax-rules ()
    [(_ p) (case p
             [(negative?) (-≥/c 0)]
             [(    zero?) (-≢/c 0)]
             [(positive?) (-≤/c 0)]
             [else (-not/c p)])]))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;; Call history
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(struct -edge ([tgt : -⟦e⟧] [src : -ℒ]) #:transparent)
(define-type -ℋ (Listof (U -edge -ℒ)))
(define-interner -⟪ℋ⟫ -ℋ
  #:intern-function-name -ℋ->-⟪ℋ⟫
  #:unintern-function-name -⟪ℋ⟫->-ℋ)

;; Encodes monitor + call site
(struct -ℒ ([mons : (℘ ℓ)] [app : ℓ]) #:transparent)


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;; Value address
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Some address values have `e` embeded in them.
;; This used to be a neccessary precision hack.
;; Nowaways it's just a temporary fix for the inaccurate source location returned
;; by `fake-contract`
(-α . ::= . ; For wrapped top-level definition
            (-α.wrp -𝒾)
            ; for binding
            (-α.x Symbol -⟪ℋ⟫ (U (℘ -h) -⟦e⟧))
            (-α.fv -⟪ℋ⟫ (℘ -t))
            ; for struct field
            (-α.fld [id : -𝒾] [loc : -ℒ] [ctx : -⟪ℋ⟫] [idx : Natural])
            ; for Cons/varargs
            ; idx prevents infinite list
            (-α.var-car [loc : -ℒ] [ctx : -⟪ℋ⟫] [idx : (Option Natural)])
            (-α.var-cdr [loc : -ℒ] [ctx : -⟪ℋ⟫] [idx : (Option Natural)])

            ;; for wrapped mutable struct
            (-α.st [id : -𝒾] [loc : -ℒ] [ctx : -⟪ℋ⟫] [l+ : -l])

            ;; for vector indices
            (-α.idx [loc : -ℒ] [ctx : -⟪ℋ⟫] [idx : Natural])
            
            ;; for vector^ content
            (-α.vct [loc : -ℒ] [ctx : -⟪ℋ⟫])

            ;; for wrapped vector
            (-α.unvct [loc : -ℒ] [ctx : -⟪ℋ⟫] [l+ : -l])

            ;; for contract components
            (-α.and/c-l [sym : -?t] [loc : ℓ] [ctx : -⟪ℋ⟫])
            (-α.and/c-r [sym : -?t] [loc : ℓ] [ctx : -⟪ℋ⟫])
            (-α.or/c-l [sym : -?t] [loc : ℓ] [ctx : -⟪ℋ⟫])
            (-α.or/c-r [sym : -?t] [loc : ℓ] [ctx : -⟪ℋ⟫])
            (-α.not/c [sym : -?t] [loc : ℓ] [ctx : -⟪ℋ⟫])
            (-α.vector/c [sym : -?t] [loc : ℓ] [ctx : -⟪ℋ⟫] [idx : Natural])
            (-α.vectorof [sym : -?t] [loc : ℓ] [ctx : -⟪ℋ⟫])
            (-α.struct/c [sym : -?t] [id : -𝒾] [loc : ℓ] [ctx : -⟪ℋ⟫] [idx : Natural])
            (-α.x/c Symbol)
            (-α.dom [sym : -?t] [loc : ℓ] [ctx : -⟪ℋ⟫] [idx : Natural])
            (-α.rst [sym : -?t] [loc : ℓ] [ctd : -⟪ℋ⟫])
            (-α.rng [sym : -?t] [loc : ℓ] [ctx : -⟪ℋ⟫] [idx : Natural])
            (-α.fn [sym : (U -?t -⟦e⟧)] [mon-loc : -ℒ] [ctx : -⟪ℋ⟫] [l+ : -l] [pc : (℘ -t)])

            ;; HACK
            (-α.hv)
            (-α.mon-x/c Symbol -⟪ℋ⟫ -l (U (℘ -h) -⟦e⟧))
            (-α.fc-x/c Symbol -⟪ℋ⟫ (U (℘ -h) -⟦e⟧))
            (-α.fn.●)
            -o
            -𝒾
            )

(define-interner ⟪α⟫ -α
  #:intern-function-name -α->⟪α⟫
  #:unintern-function-name ⟪α⟫->-α)


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;; Compiled expression
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; A computation returns set of next states
;; and may perform side effects widening mutable store(s)
(define-type -⟦e⟧ (-ρ -$ -Γ -⟪ℋ⟫ -Σ -⟦k⟧ → (℘ -ς)))
(define-type -⟦k⟧ (-A -$ -Γ -⟪ℋ⟫ -Σ     → (℘ -ς)))
(define-type -⟦o⟧ (-⟪ℋ⟫ -ℒ -Σ -Γ (Listof -W¹) → (℘ -ΓA)))
(define-type -⟦f⟧ (-$ -ℒ (Listof -W¹) -Γ -⟪ℋ⟫ -Σ -⟦k⟧ → (℘ -ς)))
(-Prim . ::= . (-⟦o⟧.boxed -⟦o⟧) (-⟦f⟧.boxed -⟦f⟧))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;; State
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Configuration
(-ς . ::= . #|block start |# (-ς↑ -αₖ -Γ -⟪ℋ⟫)
            #|block return|# (-ς↓ -αₖ -Γ -A))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;; Blocks
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Stack-address / Evaluation "check-point"
(-αₖ . ::= . (-ℬ [var : -formals] [exp : -⟦e⟧] [env : -ρ])
     ;; Contract monitoring
     (-ℳ [var : Symbol] [l³ : -l³] [loc : -ℒ] [ctc : -V] [val : ⟪α⟫])
     ;; Flat checking
     (-ℱ [var : Symbol] [l : -l] [loc : -ℒ] [ctc : -V] [val : ⟪α⟫])
     ;; Havoc
     (-ℋ𝒱)
     )