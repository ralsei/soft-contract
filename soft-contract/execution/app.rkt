#lang typed/racket/base

(provide app@)

(require racket/set
         racket/list
         racket/match
         racket/vector
         racket/pretty
         typed/racket/unit
         syntax/parse/define
         set-extras
         bnf
         unreachable
         "../utils/patterns.rkt"
         "../utils/map.rkt"
         "../ast/signatures.rkt"
         "../runtime/signatures.rkt"
         "../signatures.rkt"
         "signatures.rkt"
         )

(⟦F⟧ . ≜ . (Σ ℓ W → (Values R (℘ Err))))
(⟦G⟧ . ≜ . (Σ ℓ W V^ → (Values R (℘ Err))))

(define-unit app@
  (import meta-functions^ static-info^ ast-pretty-print^
          params^ sto^ cache^ val^ pretty-print^
          prims^ prover^
          exec^ evl^ mon^ hv^ gc^)
  (export app^)

  ;; A call history tracks the call chain that leads to the current expression, modulo loops
  (Stk . ≜ . (Listof E))
  (define current-chain ((inst make-parameter Stk) '()))
  ;; Global table remembering the widest store for each chain
  ;; FIXME: memory leak. Reset for each program.
  (define global-stores : (HashTable (Pairof Stk Σ) Σ) (make-hash))

  (: app : Σ ℓ V^ W → (Values R (℘ Err)))
  (define (app Σ ℓ Vₕ^ W*)
    (define-values (W ΔΣ) (escape-clos Σ W*))
    (define root₀ (∪ (W-root W) (B-root (current-parameters))))
    ((inst fold-ans V)
     (λ (Vₕ)
       (define root (∪ root₀ (V-root Vₕ)))
       (define Σ* (gc root (⧺ Σ ΔΣ)))
       (log-scv-preval-debug "~n~a~a ⊢ₐ:~a ~a ~a~n"
                             (make-string (* 4 (db:depth)) #\space)
                             (show-Σ Σ*)
                             (show-full-ℓ ℓ)
                             (show-V Vₕ)
                             (show-W W))
       (define-values (r es) (parameterize ([db:depth (+ (db:depth))]) (ref-$! ($:Key:App Σ* (current-parameters) ℓ Vₕ W)
                                                                               (λ () (with-gc root Σ* (λ () (with-pre ΔΣ (app₁ Σ* ℓ Vₕ W))))))))
       (log-scv-eval-debug "~n~a~a ⊢ₐ:~a ~a ~a ⇓ ~a~n"
                           (make-string (* 4 (db:depth)) #\space)
                           (show-Σ Σ*)
                           (show-full-ℓ ℓ)
                           (show-V Vₕ)
                           (show-W W)
                           (show-R r))
       (values r es))
     (unpack Vₕ^ Σ)))

  (: app/C : Σ ℓ V^ W → (Values R (℘ Err)))
  (define (app/C Σ ℓ Cs W)
    (define-values (bs Cs*) (set-partition -b? Cs))
    (define-values (r₁ es₁) (cond [(set-empty? Cs*) (values ⊥R ∅)]
                                  [else (app Σ ℓ Cs* W)]))
    (define-values (r₂ es₂) (cond [(set-empty? bs) (values ⊥R ∅)]
                                  [else (app₁ Σ ℓ 'equal? (cons bs W))]))
    (values (R⊔ r₁ r₂) (∪ es₁ es₂)))

  (: app₁ : Σ ℓ V W → (Values R (℘ Err)))
  (define (app₁ Σ ℓ V W)
    (define f (match V
                [(? -λ? V) (app-λ V)]
                [(? Clo? V) (app-Clo V)]
                [(? Case-Clo? V) (app-Case-Clo V)]
                [(-st-mk 𝒾) (app-st-mk 𝒾)]
                [(-st-p 𝒾) (app-st-p 𝒾)]
                [(-st-ac 𝒾 i) (app-st-ac 𝒾 i)]
                [(-st-mut 𝒾 i) (app-st-mut 𝒾 i)]
                [(? symbol? o) (app-prim o)]
                [(Param α) (app-param α)]
                [(Guarded ctx (? Fn/C? G) α)
                 (cond [(==>i? G)    (app-==>i ctx G α)]
                       [(∀/C? G)     (app-∀/C  ctx G α)]
                       [(Case-=>? G) (app-Case-=> ctx G α)]
                       [(Param/C? G) (app-Param/C ctx G α)]
                       [else (app-Terminating/C ctx α)])]
                [(And/C α₁ α₂ ℓ) #:when (C-flat? V Σ) (app-And/C α₁ α₂ ℓ)]
                [(Or/C  α₁ α₂ ℓ) #:when (C-flat? V Σ) (app-Or/C  α₁ α₂ ℓ)]
                [(Not/C α ℓ) (app-Not/C α ℓ)]
                [(Rec/C α) (app-Rec/C α)]
                [(One-Of/C bs) (app-One-Of/C bs)]
                [(? St/C?) #:when (C-flat? V Σ) (app-St/C V)]
                [(-● Ps) (app-opq Ps)]
                [(P:≡ T) (app-P 'equal? T)]
                [(P:= T) (app-P '= T)]
                [(P:> T) (app-P '< T)]
                [(P:≥ T) (app-P '<= T)]
                [(P:< T) (app-P '> T)]
                [(P:≤ T) (app-P '>= T)]
                [V (app-err V)]))
    (f Σ ℓ W))

  (: app-λ : -λ → ⟦F⟧)
  (define ((app-λ Vₕ) Σ ℓ Wₓ*)
    (match-define (-λ fml E ℓₕ) Vₕ)
    (cond [(arity-includes? (shape fml) (length Wₓ*))
           (match-define (-var xs xᵣ) fml)
           (define Wₓ (unpack-W Wₓ* Σ))
           (define ΔΣₓ
             (let-values ([(W₀ Wᵣ) (if xᵣ (split-at Wₓ (length xs)) (values Wₓ '()))])
               (⧺ (alloc-lex* xs W₀)
                  (if xᵣ (alloc-vararg xᵣ Wᵣ) ⊥ΔΣ))))
           ;; gc one more time against unpacked arguments
           ;; TODO: clean this up so only need to gc once?
           ;; TODO: code dup
           (let ([root (∪ (E-root Vₕ) (W-root Wₓ) (B-root (current-parameters)))])
             (define Σ₁ (gc root Σ))
             (define-values (rₐ es) (evl/history (⧺ Σ₁ ΔΣₓ) E))
             (define rn (trim-renamings (make-renamings fml Wₓ* assignable?)))
             (values (fix-return rn Σ₁ (R-escape-clos Σ₁ (ΔΣ⧺R ΔΣₓ rₐ))) es))]
          [else (err (Err:Arity ℓₕ (length Wₓ*) ℓ))]))

  (: app-Clo : Clo → ⟦F⟧)
  (define ((app-Clo Vₕ) Σ ℓ Wₓ*)
    (match-define (Clo fml E H ℓₕ) Vₕ)
    (cond [(arity-includes? (shape fml) (length Wₓ*))
           (match-define (-var xs xᵣ) fml)
           (define Wₓ (unpack-W Wₓ* Σ))
           (define ΔΣₓ
             (let-values ([(W₀ Wᵣ) (if xᵣ (split-at Wₓ (length xs)) (values Wₓ '()))])
               (⧺ (stack-copy (Clo-escapes fml E H ℓₕ) Σ)
                  (alloc-lex* xs W₀)
                  (if xᵣ (alloc-vararg xᵣ Wᵣ) ⊥ΔΣ))))
           ;; gc one more time against unpacked arguments
           ;; TODO: clean this up so only need to gc once?
           (let ([root (∪ (V-root Vₕ) (W-root Wₓ) (B-root (current-parameters)))])
             (define Σ₁ (gc root Σ))
             (define-values (rₐ es) (evl/history (⧺ Σ₁ ΔΣₓ) E)) ; no `ΔΣₓ` in result
             (define rn (trim-renamings (insert-fv-erasures ΔΣₓ (make-renamings fml Wₓ* assignable?))))
             (values (fix-return rn Σ₁ (R-escape-clos Σ₁ (ΔΣ⧺R ΔΣₓ rₐ))) es))]
          [else (err (Err:Arity ℓₕ (length Wₓ*) ℓ))]))

  (: global-stores->bindings : (HashTable (Pairof Stk Σ) Σ) → (HashTable γ (Setof S)))
  (define (global-stores->bindings res)
    (define hell : (HashTable γ (Setof S)) (make-hash))
    (for* ([(_ Σ) (in-hash res)]
           [(α Sp) (in-hash Σ)])
      (define v (car Sp))
      ; I don't know what (α:dyn β H) is and at this point I'm afraid to ask
      (when (γ? α)
        (hash-update! hell α (λ ([x : (Setof S)]) (set-add x v)) (λ () (ann (set) (Setof S))))))
    hell)

  ;; given a set of storables, convert them into just V^, stripping potential vectors
  (: storables->abstract-values : (Setof S) → (Setof V^))
  (define (storables->abstract-values storables)
    (for/fold ([not-vectors : (Setof V^) (set)])
              ([storable (in-set storables)])
      (if (vector? storable)
          (set-union not-vectors (apply set (vector->list storable)))
          (set-add not-vectors storable))))

  ;; given a set of storables, unpack them, and determine if they have any closures
  ;; if they have any closures, make sure they're closed expressions (without any free variables)
  (: all-closed? : (Setof S) → Boolean)
  (define (all-closed? storables)
    (define not-vectors : (Setof V^) (storables->abstract-values storables))
    (for/and ([storable (in-set not-vectors)])
      (set-empty?
       (V^-root
        (for/set: : V^
            ([v : V (in-set storable)]
             #:when (Fn? v))
          v)))))

  (: all-concrete? : (Setof S) → Boolean)
  (define (all-concrete? storables)
    (define not-vectors : (Setof V^) (storables->abstract-values storables))
    (for/and ([abstract-value : V^ (in-set not-vectors)])
      (for/and: : Boolean
          ([value : V (in-set abstract-value)])
        (not (-●? value)))))

  (: find-singletons : (HashTable γ (Setof S)) → (Setof γ))
  (define (find-singletons vars)
    ;; first attempt: just try and get everything with only one thing in its set
    ;; ensure we don't have a symbolic value, or a lambda with free variables
    (for/set: : (Setof γ)
        ([(var binds) (in-hash vars)]
         #:when (and (= (set-count binds) 1)
                     (all-closed? binds)
                     (all-concrete? binds)))
      var))

  (: evl/history : Σ E → (Values R (℘ Err)))
  (define (evl/history Σ₁ E)
    (define stk (current-chain))
    (define stk* (cond [(memq E stk) => values]
                       [else (cons E stk)]))
    (define k (cons stk* (Σ-stk Σ₁)))
    (define Σ* (match (hash-ref global-stores k #f)
                 [(? values Σ₀) (ΔΣ⊔ Σ₀ Σ₁)]
                 [_ Σ₁]))
    (hash-set! global-stores k Σ*)

    (for ([γ (in-set (find-singletons (global-stores->bindings global-stores)))])
      (display (format "~a " (show-α γ))))
    (newline)
    ;; (pretty-print global-stores)
    (displayln "-------")

    (parameterize ([current-chain stk*])
      (evl Σ* E)))

  (: Σ-stk : Σ → Σ)
  (define (Σ-stk Σ₀)
    (for/fold ([Σ* : Σ Σ₀]) ([α (in-hash-keys Σ₀)] #:unless (γ:lex? α))
      (hash-remove Σ* α)))

  (: app-Case-Clo : Case-Clo → ⟦F⟧)
  (define ((app-Case-Clo Vₕ) Σ ℓ Wₓ)
    (match-define (Case-Clo cases ℓₕ) Vₕ)
    (define n (length Wₓ))
    (match ((inst findf Clo) (λ (clo) (arity-includes? (shape (Clo-_0 clo)) n)) cases)
      [(? values clo) ((app-Clo clo) Σ ℓ Wₓ)]
      [#f (err (Err:Arity ℓₕ n ℓ))]))

  (: app-st-mk : -𝒾 → ⟦F⟧)
  (define ((app-st-mk 𝒾) Σ ℓ Wₓ)
    (define n (count-struct-fields 𝒾))
    (if (= n (length Wₓ))
        (let ([α (α:dyn (β:st-elems ℓ 𝒾) H₀)])
          (just (St α ∅) (alloc α (list->vector (unpack-W Wₓ Σ)))))
        (err (Err:Arity (-st-mk 𝒾) (length Wₓ) ℓ))))

  (: app-st-p : -𝒾 → ⟦F⟧)
  (define ((app-st-p 𝒾) Σ ℓ Wₓ)
    (with-guarded-arity Wₓ (-st-p 𝒾) ℓ
      [(list _) (implement-predicate Σ (-st-p 𝒾) Wₓ)]))

  (: app-st-ac : -𝒾 Index → ⟦F⟧)
  (define ((app-st-ac 𝒾 i) Σ ℓ Wₓ)
    (with-guarded-arity Wₓ (-st-ac 𝒾 i) ℓ
      [(list Vₓ)
       (with-split-Σ Σ (-st-p 𝒾) Wₓ
         (λ (Wₓ* ΔΣ₁) (with-pre ΔΣ₁ ((unchecked-app-st-ac 𝒾 i) (⧺ Σ ΔΣ₁) ℓ (car Wₓ*))))
         (λ (Wₓ* ΔΣ₂)
           (define ℓₒ (ℓ-with-src +ℓ₀ (show-o (-st-ac 𝒾 i))))
           (err (blm (ℓ-src ℓ) ℓ ℓₒ (list {set (-st-p 𝒾)}) Wₓ*))))]))

  (: unchecked-app-st-ac : -𝒾 Index → Σ ℓ V^ → (Values R (℘ Err)))
  (define ((unchecked-app-st-ac 𝒾 i) Σ ℓ Vₓ)
    (define ac₁ : (V → (Values R (℘ Err)))
      (match-lambda
        [(St α Ps)
         (define Vᵢ (vector-ref (Σ@/blob α Σ) i))
         (define-values (V* ΔΣ)
           (refine (unpack Vᵢ Σ) (ac-Ps (-st-ac 𝒾 i) Ps) Σ))
         (just V* ΔΣ)]
        [(and T (or (? T:@?) (? γ?))) #:when (not (struct-mutable? 𝒾 i))
                                      (define T* (T:@ (-st-ac 𝒾 i) (list T)))
                                      (if (set-empty? (unpack T* Σ)) (values ⊥R ∅) (just T*))]
        [(Guarded (cons l+ l-) (? St/C? C) αᵥ)
         (define-values (αₕ ℓₕ _) (St/C-fields C))
         (define Cᵢ (vector-ref (Σ@/blob αₕ Σ) i))
         (with-collapsing/R [(ΔΣ Ws) ((unchecked-app-st-ac 𝒾 i) Σ ℓ (unpack αᵥ Σ))]
           (with-pre ΔΣ (mon (⧺ Σ ΔΣ) (Ctx l+ l- ℓₕ ℓ) Cᵢ (car (collapse-W^ Ws)))))]
        [(and V₀ (-● Ps))
         (case (sat Σ (-st-p 𝒾) {set V₀})
           [(✗) (values ⊥R ∅)]
           [else (just (st-ac-● 𝒾 i Ps Σ))])]
        [(? α? α) (fold-ans ac₁ (unpack α Σ))]
        [_ (values ⊥R ∅)]))
    
    (fold-ans/collapsing ac₁ Vₓ))

  (: st-ac-● : -𝒾 Index (℘ P) Σ → V^)
  (define (st-ac-● 𝒾 i Ps Σ)
    (define V
      (if (prim-struct? 𝒾)
          {set (-● ∅)}
          ;; Track access to user-defined structs
          (Σ@ (γ:escaped-field 𝒾 i) Σ)))
    (cond [(set-empty? V) ∅]
          [else (define-values (V* _) (refine V (ac-Ps (-st-ac 𝒾 i) Ps) Σ))
                V*]))

  (: app-st-mut : -𝒾 Index → ⟦F⟧)
  (define ((app-st-mut 𝒾 i) Σ ℓ Wₓ)
    (with-guarded-arity Wₓ (-st-mut 𝒾 i) ℓ
      [(list Vₓ V*)
       (with-split-Σ Σ (-st-p 𝒾) (list Vₓ)
         (λ (Wₓ* ΔΣ₁) (with-pre ΔΣ₁ ((unchecked-app-st-mut 𝒾 i) (⧺ Σ ΔΣ₁) ℓ (car Wₓ*) V*)))
         (λ (Wₓ* ΔΣ₂) (err (blm (ℓ-src ℓ) ℓ (ℓ-with-src +ℓ₀ (show-o (-st-mut 𝒾 i))) (list {set (-st-p 𝒾)}) Wₓ*))))]))

  (: unchecked-app-st-mut : -𝒾 Index → Σ ℓ V^ V^ → (Values R (℘ Err)))
  (define ((unchecked-app-st-mut 𝒾 i) Σ ℓ Vₓ V*)
    ((inst fold-ans V)
     (match-lambda
       [(St α _)
        (define S (Σ@/blob α Σ))
        (define S* (vector-copy S))
        (vector-set! S* i V*)
        (just -void (mut α S* Σ))]
       [(Guarded (cons l+ l-) (? St/C? C) αᵥ)
        (define-values (αₕ ℓₕ _) (St/C-fields C))
        (define Cᵢ (vector-ref (Σ@/blob αₕ Σ) i))
        (with-collapsing/R [(ΔΣ Ws) (mon Σ (Ctx l- l+ ℓₕ ℓ) Cᵢ V*)]
          (with-pre ΔΣ ((unchecked-app-st-mut 𝒾 i) (⧺ Σ ΔΣ) ℓ (unpack αᵥ Σ) V*)))]
       [(? -●?) (just -void (alloc (γ:hv #f) V*))]
       [_ (values ⊥R ∅)])
     (unpack Vₓ Σ)))

  (: app-prim : Symbol → ⟦F⟧)
  (define ((app-prim o) Σ ℓ Wₓ)
    ; TODO massage raw result
    ((get-prim o) Σ ℓ Wₓ))

  (: app-param : α → ⟦F⟧)
  (define ((app-param α) Σ ℓ Wₓ)
    (match Wₓ
      [(list) (just (current-parameter α))]
      [(list V) (set-parameter α V)
                (just -void)]
      [_ (err (Err:Arity (Param α) (length Wₓ) ℓ))]))

  (: app-==>i : (Pairof -l -l) ==>i α → ⟦F⟧)
  (define ((app-==>i ctx:saved G αₕ) Σ₀-full ℓ Wₓ*)
    (match-define (cons l+ l-) ctx:saved)
    (define Wₓ (unpack-W Wₓ* Σ₀-full))
    (define Σ₀ (gc (∪ (set-add (V-root G) αₕ) (W-root Wₓ) (B-root (current-parameters))) Σ₀-full))
    (match-define (==>i (-var Doms ?Doms:rest) Rngs) G)

    (: mon-doms : Σ -l -l (Listof Dom) W → (Values R (℘ Err)))
    (define (mon-doms Σ₀ l+ l- Doms₀ Wₓ₀)
      (let go ([Σ : Σ Σ₀] [Doms : (Listof Dom) Doms₀] [Wₓ : W Wₓ₀])
        (match* (Doms Wₓ)
          [('() '()) (values (R-of '()) ∅)]
          [((cons Dom Doms) (cons Vₓ Wₓ))
           (with-each-ans ([(ΔΣₓ Wₓ*) (mon-dom Σ l+ l- Dom Vₓ)]
                           [(ΔΣ* W*) (go (⧺ Σ ΔΣₓ) Doms Wₓ)])
             (just (cons (car Wₓ*) W*) (⧺ ΔΣₓ ΔΣ*)))]
          [(_ _)
           (err (blm l+ ℓ #|FIXME|# (ℓ-with-src +ℓ₀ 'Λ) (map (compose1 (inst set V) Dom-ctc) Doms₀) Wₓ₀))])))

    (: mon-dom : Σ -l -l Dom V^ → (Values R (℘ Err)))
    (define (mon-dom Σ l+ l- dom V)
      (match-define (Dom x c ℓₓ) dom)
      (define ctx (Ctx l+ l- ℓₓ ℓ))
      (match c
        ;; Dependent domain
        [(Clo (-var xs #f) E H ℓ)
         (define ΔΣ₀ (stack-copy (Clo-escapes xs E H ℓ) Σ))
         (define Σ₀ (⧺ Σ ΔΣ₀))
         (with-each-ans ([(ΔΣ₁ W) (evl Σ₀ E)]
                         [(ΔΣ₂ W) (mon (⧺ Σ₀ ΔΣ₁) ctx (car W) V)])
           (match-define (list V*) W) ; FIXME catch
           (just W (⧺ ΔΣ₀ ΔΣ₁ ΔΣ₂ (alloc (γ:lex x) V*))))]
        ;; Non-dependent domain
        [(? α? α)
         (with-each-ans ([(ΔΣ W) (mon Σ ctx (Σ@ α Σ₀) V)])
           (match-define (list V*) W)
           (just W (⧺ ΔΣ (alloc (γ:lex x) V*))))]))

    (define Dom-ref (match-lambda [(Dom x _ _) {set (γ:lex x)}]))

    (define (with-result [ΔΣ-acc : ΔΣ] [comp : (→ (Values R (℘ Err)))]) 
      (define-values (r es)
        (if Rngs
            (with-each-ans ([(ΔΣₐ Wₐ) (comp)])
              (with-pre (⧺ ΔΣ-acc ΔΣₐ) (mon-doms (⧺ Σ₀ ΔΣ-acc ΔΣₐ) l+ l- Rngs Wₐ)))
            (with-pre ΔΣ-acc (comp))))
      (define rn (for/hash : (Immutable-HashTable α (Option α))
                     ([d (in-list Doms)]
                      [Vₓ (in-list Wₓ*)])
                   (values (γ:lex (Dom-name d))
                           (match Vₓ
                             [{singleton-set (? α? α)}
                              ;; renaming is only valid for values monitored by
                              ;; flat contract
                              #:when (and (α? (Dom-ctc d))
                                          (C^-flat? (unpack (Dom-ctc d) Σ₀) Σ₀))
                              α]
                             [_ #f]))))
      (values (fix-return rn Σ₀ r) es))

    (with-guarded-arity Wₓ G ℓ
      [Wₓ
       #:when (and (not ?Doms:rest) (= (length Wₓ) (length Doms)))
       (with-each-ans ([(ΔΣₓ _) (mon-doms Σ₀ l- l+ Doms Wₓ)])
         (define args (map Dom-ref Doms))
         (with-result ΔΣₓ (λ () (app (⧺ Σ₀ ΔΣₓ) (ℓ-with-src ℓ l+) (Σ@ αₕ Σ₀) args))))]
      [Wₓ
       #:when (and ?Doms:rest (>= (length Wₓ) (length Doms)))
       (define-values (W₀ Wᵣ) (split-at Wₓ (length Doms)))
       (define-values (Vᵣ ΔΣᵣ) (alloc-rest (Dom-loc ?Doms:rest) Wᵣ))
       (with-each-ans ([(ΔΣ-init _) (mon-doms Σ₀ l- l+ Doms W₀)]
                       [(ΔΣ-rest _) (mon-dom (⧺ Σ₀ ΔΣ-init ΔΣᵣ) l- l+ ?Doms:rest Vᵣ)])
         (define args-init (map Dom-ref Doms))
         (define arg-rest (Dom-ref ?Doms:rest))
         (with-result (⧺ ΔΣ-init ΔΣᵣ ΔΣ-rest)
           (λ () (app/rest (⧺ Σ₀ ΔΣ-init ΔΣᵣ ΔΣ-rest) (ℓ-with-src ℓ l+) (Σ@ αₕ Σ₀) args-init arg-rest))))]))

  (: app-∀/C : (Pairof -l -l) ∀/C α → ⟦F⟧)
  (define ((app-∀/C ctx G α) Σ₀ ℓ Wₓ)
    (with-each-ans ([(ΔΣ Wₕ) (inst-∀/C Σ₀ ctx G α ℓ)])
      (with-pre ΔΣ (app (⧺ Σ₀ ΔΣ) ℓ (car Wₕ) Wₓ))))

  (: app-Case-=> : (Pairof -l -l) Case-=> α → ⟦F⟧)
  (define ((app-Case-=> ctx G α) Σ ℓ Wₓ)
    (define n (length Wₓ))
    (match-define (Case-=> Cs) G)
    (match ((inst findf ==>i)
            (match-lambda [(==>i doms _) (arity-includes? (shape doms) n)])
            Cs)
      [(? values C) ((app-==>i ctx C α) Σ ℓ Wₓ)]
      [#f (err (Err:Arity G n ℓ))]))

  (: app-Param/C : (Pairof -l -l) Param/C α → ⟦F⟧)
  (define ((app-Param/C ctx:saved G α) Σ ℓ Wₓ)
    (match-define (cons l+ l-) ctx:saved)
    (match-define (Param/C αₕ ℓₕ) G)
    (define ctx (Ctx l+ l- ℓₕ ℓ))
    (define C (Σ@ αₕ Σ))
    (match Wₓ
      [(list)
       (with-collapsing/R [(ΔΣ (app collapse-W^ (list V))) (app Σ (ℓ-with-src ℓ l+) (Σ@ α Σ) '())]
         (with-pre ΔΣ
           (mon (⧺ Σ ΔΣ) ctx C V)))]
      [(list V)
       (with-collapsing/R [(ΔΣ Ws) (mon Σ (Ctx l- l+ ℓₕ ℓ) C V)]
         (with-pre ΔΣ
           (app (⧺ Σ ΔΣ) (ℓ-with-src ℓ l+) (Σ@ α Σ) (collapse-W^ Ws))))]
      [_ (err (Err:Arity G (length Wₓ) ℓ))]))

  (: app-Terminating/C : Ctx α → ⟦F⟧)
  (define ((app-Terminating/C ctx α) Σ ℓ Wₓ)
    ???)

  (: app-And/C : α α ℓ → ⟦F⟧)
  (define ((app-And/C α₁ α₂ ℓₕ) Σ ℓ Wₓ)
    (with-guarded-arity Wₓ ℓₕ ℓ
      [(list _)
       (with-each-ans ([(ΔΣ₁ W₁) (app/C Σ ℓ (unpack α₁ Σ) Wₓ)])
         (define Σ₁ (⧺ Σ ΔΣ₁))
         (with-split-Σ Σ₁ 'values W₁
           (λ (_ ΔΣ*) (with-pre (⧺ ΔΣ₁ ΔΣ*) (app/C (⧺ Σ₁ ΔΣ*) ℓ (unpack α₂ Σ) Wₓ)))
           (λ (_ ΔΣ*) (values (R-of -ff (⧺ ΔΣ₁ ΔΣ*)) ∅))))]))

  (: app-Or/C : α α ℓ → ⟦F⟧)
  (define ((app-Or/C α₁ α₂ ℓₕ) Σ ℓ Wₓ)
    (with-guarded-arity Wₓ ℓₕ ℓ
      [(list _)
       (with-each-ans ([(ΔΣ₁ W₁) (app/C Σ ℓ (unpack α₁ Σ) Wₓ)])
         (define Σ₁ (⧺ Σ ΔΣ₁))
         (with-split-Σ Σ₁ 'values W₁
           (λ (_ ΔΣ*) (values (R-of W₁ (⧺ ΔΣ₁ ΔΣ*)) ∅))
           (λ (_ ΔΣ*) (with-pre (⧺ ΔΣ₁ ΔΣ*) (app/C (⧺ Σ₁ ΔΣ*) ℓ (unpack α₂ Σ) Wₓ)))))]))

  (: app-Not/C : α ℓ → ⟦F⟧)
  (define ((app-Not/C α ℓₕ) Σ ℓ Wₓ)
    (with-guarded-arity Wₓ ℓₕ ℓ
      [(list _)
       (with-each-ans ([(ΔΣ W) (app/C Σ ℓ (unpack α Σ) Wₓ)])
         (define Σ* (⧺ Σ ΔΣ))
         (with-split-Σ Σ* 'values W
           (λ (_ ΔΣ*) (just -ff (⧺ ΔΣ ΔΣ*)))
           (λ (_ ΔΣ*) (just -tt (⧺ ΔΣ ΔΣ*)))))]))

  (: app-Rec/C : α → ⟦F⟧)
  (define ((app-Rec/C α) Σ ℓ Wₓ) (app/C Σ ℓ (unpack α Σ) (unpack-W Wₓ Σ)))

  (: app-One-Of/C : (℘ Base) → ⟦F⟧)
  (define ((app-One-Of/C bs) Σ ℓ Wₓ)
    (with-guarded-arity Wₓ (One-Of/C bs) ℓ
      [(list V)
       (with-split-Σ Σ (One-Of/C bs) Wₓ
         (λ (_ ΔΣ) (just -tt ΔΣ))
         (λ (_ ΔΣ) (just -ff ΔΣ)))]))

  (: app-St/C : St/C → ⟦F⟧)
  (define ((app-St/C C) Σ ℓ Wₓ)
    (define-values (α ℓₕ 𝒾) (St/C-fields C))
    (define S (Σ@/blob α Σ))
    (with-guarded-arity Wₓ ℓₕ ℓ
      [(list Vₓ)
       (with-split-Σ Σ (-st-p 𝒾) Wₓ
         (λ (Wₓ* ΔΣ*) (with-pre ΔΣ* ((app-St/C-fields 𝒾 0 S ℓₕ) (⧺ Σ ΔΣ*) ℓ (car Wₓ*))))
         (λ (_ ΔΣ*) (just -ff ΔΣ*)))]))

  (: app-St/C-fields : -𝒾 Index (Vectorof V^) ℓ → Σ ℓ V^ → (Values R (℘ Err)))
  (define ((app-St/C-fields 𝒾 i Cs ℓₕ) Σ₀ ℓ Vₓ)
    (let loop ([i : Index 0] [Σ : Σ Σ₀])
      (if (>= i (vector-length Cs))
          (just -tt)
          (with-collapsing/R [(ΔΣᵢ Wᵢs) ((unchecked-app-st-ac 𝒾 i) Σ ℓ Vₓ)]
            (with-each-ans ([(ΔΣₜ Wₜ) (app/C (⧺ Σ ΔΣᵢ) ℓ (vector-ref Cs i) (collapse-W^ Wᵢs))])
              (define ΔΣ (⧺ ΔΣᵢ ΔΣₜ))
              (define Σ* (⧺ Σ ΔΣ))
              (with-split-Σ Σ* 'values Wₜ
                (λ _ (with-pre ΔΣ (loop (assert (+ 1 i) index?) Σ*)))
                (λ _ (just -ff ΔΣ))))))))

  (: app-opq : (℘ P) → ⟦F⟧)
  (define ((app-opq Ps) Σ ℓ Wₓ*)
    (define Wₕ (list {set (-● Ps)}))
    (define ℓₒ (ℓ-with-src +ℓ₀ 'Λ))
    (with-split-Σ Σ 'procedure? Wₕ
      (λ _
        (define P-arity (P:arity-includes (length Wₓ*)))
        (with-split-Σ Σ P-arity Wₕ
          (λ _ (leak Σ (γ:hv #f) ((inst foldl V^ V^) ∪ ∅ (unpack-W Wₓ* Σ))))
          (λ _ (err (blm (ℓ-src ℓ) ℓ ℓₒ (list {set P-arity}) Wₕ)))))
      (λ _ (err (blm (ℓ-src ℓ) ℓ ℓₒ (list {set 'procedure?}) Wₕ)))))

  (: app-P : Symbol (U T -b) → ⟦F⟧)
  (define ((app-P o T) Σ ℓ Wₓ) ((app-prim o) Σ ℓ (cons {set T} Wₓ)))

  (: app-err : V → ⟦F⟧)
  (define ((app-err V) Σ ℓ Wₓ)
    (err (blm (ℓ-src ℓ) ℓ (ℓ-with-src +ℓ₀ 'Λ) (list {set 'procedure?}) (list {set V}))))

  (: app/rest : Σ ℓ V^ W V^ → (Values R (℘ Err)))
  (define (app/rest Σ ℓ Vₕ^ Wₓ Vᵣ)
    (define args:root (∪ (W-root Wₓ) (V^-root Vᵣ)))
    (define-values (Wᵣs snd?) (unalloc Vᵣ Σ))
    (define-values (r es) (fold-ans (λ ([Wᵣ : W]) (app Σ ℓ Vₕ^ (append Wₓ Wᵣ))) Wᵣs))
    (values r (if snd? es (set-add es (Err:Varargs Wₓ Vᵣ ℓ)))))

  (: trim-renamings : Renamings → Renamings)
  ;; Prevent some renaming from propagating based on what the caller has
  (define (trim-renamings rn)
    (for/fold ([rn : Renamings rn])
              ([(x ?T) (in-hash rn)]
               ;; FIXME this erasure is too aggressive
               #:when (T:@? ?T))
      (hash-set rn x #f)))

  (: insert-fv-erasures : ΔΣ Renamings → Renamings)
  ;; Add erasure of free variables that were stack-copied
  (define (insert-fv-erasures ΔΣ rn)
    (for/fold ([rn : Renamings rn]) ([α (in-hash-keys ΔΣ)]
                                     #:unless (hash-has-key? rn α))
      (hash-set rn α #f)))

  (: unalloc : V^ Σ → (Values (℘ W) Boolean))
  ;; Convert list in object language into one in meta-language
  (define (unalloc Vs Σ)
    (define-set touched : α #:mutable? #t)
    (define elems : (Mutable-HashTable Integer V^) (make-hasheq))
    (define-set ends : Integer #:eq? #t #:mutable? #t)
    (define sound? : Boolean #t)

    (let touch! ([i : Integer 0] [Vs : V^ Vs])
      (for ([V (in-set Vs)])
        (match V
          [(St (and α (α:dyn (β:st-elems _ (== -𝒾-cons)) _)) _)
           (match-define (vector Vₕ Vₜ) (Σ@/blob α Σ))
           (hash-update! elems i (λ ([V₀ : V^]) (V⊔ V₀ Vₕ)) mk-∅)
           (cond [(touched-has? α)
                  (set! sound? #f)
                  (ends-add! (+ 1 i))]
                 [else (touched-add! α)
                       (touch! (+ 1 i) Vₜ)])]
          [(-b '()) (ends-add! i)]
          [_ (set! sound? #f)
             (ends-add! i)])))

    (define Ws (for/set: : W^ ([n (in-ends)])
                 (for/list : W ([i (in-range n)]) (hash-ref elems i))))
    (values Ws sound?))

  (: inst-∀/C : Σ (Pairof -l -l) ∀/C α ℓ → (Values R (℘ Err)))
  ;; Monitor function against freshly instantiated parametric contract
  (define (inst-∀/C Σ₀ ctx G α ℓ)
    (match-define (∀/C xs c H ℓₒ) G)
    (match-define (cons l+ (and l- l-seal)) ctx)
    (define ΔΣ₀
      (let ([ΔΣ:seals
             (for/fold ([acc : ΔΣ ⊥ΔΣ]) ([x (in-list xs)])
               (define αₓ (α:dyn (β:sealed x ℓ) H₀))
               (⧺ acc
                  (alloc αₓ ∅)
                  (alloc (γ:lex x) {set (Seal/C αₓ l-seal)})))]
            [ΔΣ:stk (stack-copy (Clo-escapes xs c H ℓₒ) Σ₀)])
        (⧺ ΔΣ:seals ΔΣ:stk)))
    (define Σ₁ (⧺ Σ₀ ΔΣ₀))
    (with-each-ans ([(ΔΣ₁ W:c) (evl Σ₁ c)])
      (with-pre (⧺ ΔΣ₀ ΔΣ₁)
        (mon (⧺ Σ₁ ΔΣ₁) (Ctx l+ l- ℓₒ ℓ) (car W:c) (Σ@ α Σ₀)))))

  (define-simple-macro (with-guarded-arity W f ℓ [p body ...] ...)
    (match W
      [p body ...] ...
      [_ (err (Err:Arity f (length W) ℓ))])))
