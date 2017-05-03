#lang typed/racket/base

(provide (all-defined-out))

(require typed/racket/unit
         set-extras
         "../ast/main.rkt"
         "../runtime/main.rkt")

(define-signature local-prover^
  ([Γ⊢t : ((℘ -t) -?t → -R)]
   [⊢V : (-V → -R)]
   [p∋Vs : (-σ (U -h -v -V) -V * → -R)]
   [p⇒p : (-h -h → -R)]
   [ps⇒p : ((℘ -h) -h → -R)]
   [plausible-V-t? : ((℘ -t) -V -?t → Boolean)]
   [sat-one-of : (-V (Listof Base) → -R)]
   [V-arity : (-V → (Option Arity))]))

(define-signature external-prover^
  ([ext-prove : (-M -Γ -t → -R)]))