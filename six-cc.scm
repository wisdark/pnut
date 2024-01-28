#!/usr/bin/env gsi

(define support-addr-of? #f)

(define (function-name ident)
  (string-append "_" (symbol->string (cadr ident))))

(define-type ctx
  glo-decls
  loc-env
  level
  tail?)

(define (ctx-add-glo-decl! ctx decl)
  (ctx-glo-decls-set! ctx (cons (cons decl (ctx-level ctx)) (ctx-glo-decls ctx))))

(define (nest-level ctx f)
  (ctx-level-set! ctx (+ (ctx-level ctx) 1))
  (f)
  (ctx-level-set! ctx (- (ctx-level ctx) 1)))

(define-macro (nest ctx . body)
  `(nest-level ,ctx (lambda () ,@body)))

(define (global-var ident)
  (string-append "_" (symbol->string (cadr ident))))

(define (global-ref ident)
  (if support-addr-of?
      (string-append "_$" (global-var ident))
      (global-var ident)))

(define (comp-glo-decl ctx ast)
  (case (car ast)

    ((six.define-variable)
     (comp-glo-define-variable ctx ast))

    ((six.define-procedure)
     (comp-glo-define-procedure ctx ast))

    (else
     (error "unknown global declaration" ast))))

(define (comp-constant ctx ast)
  (case (car ast)
    ((six.literal)
     (let ((val (cadr ast)))
       (cond ((exact-integer? val)
              (number->string val))
             (else
              "unknown literal" ast))))
    (else
     (error "unknown constant" ast))))

(define (comp-glo-define-variable ctx ast)
  (let* ((name (cadr ast))
         (type (caddr ast))
         (dims (cadddr ast))
         (init (car (cddddr ast))))
    (if (pair? dims)
        (let ((size
               (apply * (map (lambda (x) (cadr x)) dims))))
          (ctx-add-glo-decl!
           ctx
           (list "defarr " (global-var name) " " size)))
        (let ((val (if init (comp-constant ctx init) "0")))
          (ctx-add-glo-decl!
           ctx
           (if support-addr-of?
               (list "defglo_pointable " (global-var name) " " val)
               (list "defglo " (global-var name) " " val)))))))

(define (comp-loc-define-variable ctx ast)
  (let* ((name (cadr ast))
         (type (caddr ast))
         (dims (cadddr ast))
         (init (car (cddddr ast))))
    (if (pair? dims)
        (error "arrays not yet supported" dims)
        (let ((val (if init (comp-constant ctx init) "0")))
          (ctx-add-glo-decl!
           ctx
           (if support-addr-of?
               (list "defglo_pointable " (global-var name) " " val)
               (list "defglo " (global-var name) " " val)))))))

(define (comp-glo-define-procedure ctx ast)
  (let* ((name (cadr ast))
         (proc (caddr ast))
         (result-type (cadr proc))
         (parameters (caddr proc))
         (body (cdar (cdddr proc))))
    ;;    (print "#") (write ast) (newline)
    (ctx-add-glo-decl!
     ctx
     (list (function-name name) "() {"))
    (ctx-tail?-set! ctx #t)
    (nest ctx (comp-body ctx body))

    (ctx-add-glo-decl!
     ctx
     (list "}"))))

(define (comp-body ctx lst)
  (let ((start-loc-env (ctx-loc-env ctx)))
    (let loop ((lst lst))
      (if (and (pair? lst) (eq? (caar lst) 'six.define-variable))
          (let ((def-var (car lst)))
            (ctx-loc-env-set! ctx (cons def-var (ctx-loc-env ctx)))
            (loop (cdr lst)))
          (begin
            (comp-statement-list ctx lst)
            (ctx-loc-env-set! ctx start-loc-env))))))

(define (comp-statement-list ctx lst)
  (let ((start-tail? (ctx-tail? ctx)))
    (ctx-tail?-set! ctx #f)
    (let loop ((lst lst))
      (if (pair? lst)
          (begin
            (if (not (pair? (cdr lst)))
                (ctx-tail?-set! ctx start-tail?))
            (comp-statement ctx (car lst))
            (loop (cdr lst)))
          (ctx-tail?-set! ctx start-tail?)))))

(define (comp-statement ctx ast)
  (case (car ast)
    ((six.while)
     (if #t ;; simple-expression
         (let ((code-test (comp-test ctx (cadr ast))))
           (ctx-add-glo-decl!
            ctx
            (list "while " code-test " ; do"))
           (print "Compiling while body\n\n\n")
           (nest ctx (comp-statement ctx (caddr ast)))
           (ctx-add-glo-decl!
            ctx
            (list "done")))
         (error "complex expression not yet supported")))
    ((six.for)
     ;;(six.for (six.x=y (six.identifier i) (six.literal 0))     (six.x<y (six.identifier i) (six.literal 2800))    (six.x++ (six.i...
     (let ((expr1 (cadr ast))
           (expr2 (caddr ast))
           (expr3 (cadddr ast))
           (stat (car (cddddr ast))))
       (comp-statement ctx expr1)
       ;; TODO: support "continue"
       (let ((code-test (if expr2 (comp-test ctx expr2) ":")))
         (ctx-add-glo-decl!
          ctx
          (list "while " code-test " ; do"))
         (nest ctx
          (comp-statement ctx stat)
          (if expr3 (comp-statement ctx expr3))
         )
         (ctx-add-glo-decl!
          ctx
          (list "done")))))
    ((six.if)
     (let ((test (cadr ast))
           (stat (caddr ast)))
       (let ((code-test (comp-test ctx test)))
         (ctx-add-glo-decl!
          ctx
          (list "if " code-test " ; then"))
         (nest ctx (comp-statement ctx stat))
         (if (pair? (cdddr ast))
             (begin
               (ctx-add-glo-decl!
                ctx
                (list "else"))
               (nest ctx (comp-statement ctx (cadddr ast)))))
         (ctx-add-glo-decl!
          ctx
          (list "fi")))))
    ((six.return)
     (if (pair? (cdr ast))
         (let ((code-expr (comp-rvalue ctx (cadr ast))))
           (ctx-add-glo-decl!
            ctx
            (list ": $(( _0result = " code-expr " ))"))))
     (if (not (ctx-tail? ctx))
         (ctx-add-glo-decl!
          ctx
          (list "return"))))
    ((six.break)
     (ctx-add-glo-decl!
      ctx
      (list "break")))
    (else
     (comp-statement-expr ctx ast))))

(define (comp-test ctx ast)
  (string-append
   "[ 0 != $(( "
   (comp-rvalue ctx ast)
   " )) ]"))

(define (comp-statement-expr ctx ast)
  (case (car ast)
    ((six.call)
     (let ((name (cadr ast))
           (params (cddr ast)))
       (let ((code-params
              (map (lambda (p) (string-append "$((" (comp-rvalue ctx p) "))")) params)))
         (ctx-add-glo-decl!
          ctx
          (list
           (string-concatenate
            (cons (function-name name) code-params)
            " "))))))
    ((six.compound)
     (comp-body ctx (cdr ast)))
    ((six.x=y)
     (comp-assignment ctx ast))
    (else
     (ctx-add-glo-decl!
      ctx
      (list ": $(( " (comp-rvalue ctx ast) " ))")))))

(define (comp-glo-decl-list ctx ast)
  (if (pair? ast)
      (let ((decl (car ast)))
        (if (eq? (car decl) 'six.x=y) ;; allow assignments at top level
            (comp-assignment ctx decl 0)
            (comp-glo-decl ctx decl))
        (comp-glo-decl-list ctx (cdr ast)))))

(define (comp-assignment ctx ast)
  (let ((lhs (cadr ast))
        (rhs (caddr ast)))
    (case (car lhs)
      ((six.identifier six.index)
       (ctx-add-glo-decl!
        ctx
        (list ": $(( " (comp-lvalue ctx lhs) " = " (comp-rvalue ctx rhs) " ))")))
      (else
       (error "unknown lhs" lhs)))))

(define (comp-lvalue ctx ast)
  (case (car ast)
    ((six.identifier)
     (global-ref ast))
    ((six.index)
     (string-append "_$((" (comp-array-lvalue ctx (cadr ast)) "+" (comp-rvalue ctx (caddr ast)) "))"))
    (else
     (error "unknown lvalue" ast))))

(define (comp-array-lvalue ctx ast)
  (case (car ast)
    ((six.identifier)
     (global-var ast))
    (else
     (error "unknown array lvalue" ast))))

(define (comp-rvalue ctx ast)
  (case (car ast)
    ((six.literal)
     (let ((val (cadr ast)))
       (cond ((exact-integer? val)
              (number->string val))
             (else
              "unknown literal" ast))))
    ((six.identifier)
     (global-ref ast))
    ((six.x+y six.x-y six.x*y six.x/y six.x%y six.x==y six.x!=y six.x<y six.x>y six.x<=y six.x>=y)
     (string-append "("
                    (comp-rvalue ctx (cadr ast))
                    (case (car ast)
                      ((six.x+y) " + ")
                      ((six.x-y) " - ")
                      ((six.x*y) " * ")
                      ((six.x/y) " / ")
                      ((six.x%y) " % ")
                      ((six.x==y) " == ")
                      ((six.x!=y) " != ")
                      ((six.x<y) " < ")
                      ((six.x>y) " > ")
                      ((six.x<=y) " <= ")
                      ((six.x>=y) " >= "))
                    (comp-rvalue ctx (caddr ast))
                    ")"))
    ((six.index)
     (string-append "_$((" (comp-array-lvalue ctx (cadr ast)) "+" (comp-rvalue ctx (caddr ast)) "))"))
    ((six.x++)
     (string-append (comp-lvalue ctx (cadr ast)) " += 1"))
    ((six.x--)
     (string-append (comp-lvalue ctx (cadr ast)) " -= 1"))
    ((six.x+=y)
     (string-append (comp-lvalue ctx (cadr ast)) " += " (comp-rvalue ctx (caddr ast))))
    (else
     (error "unknown rvalue" ast))))

(define (comp-program ast)
  (let ((ctx (make-ctx '() '() 0 #f)))
    (comp-glo-decl-list ctx ast)
    (codegen ctx)))

(define (codegen ctx)
  (println runtime-prelude)
  (for-each (lambda (decl)
              (let ((level (cdr decl)))
                (if (not (zero? level))
                    (print (make-string (* 2 level) #\space)))
                (println (car decl))))
            (reverse (ctx-glo-decls ctx)))
  (println runtime-postlude))

(define runtime-prelude
  (string-append
   "_putchar() { printf \\\\$(($1/64))$(($1/8%8))$(($1%8)) ; }\n"
   "ALLOC=0\n"
   "defarr() { : $(($1 = ALLOC)) $((ALLOC = ALLOC+$2)) ; }\n"
   (if support-addr-of?
       (string-append
        "defglo_pointable() { : $(($1 = ALLOC)) $((_$ALLOC = $2)) $((ALLOC = ALLOC+1)) ; }\n")
       (string-append
        "defglo() { : $(($1 = $2)) ; }\n"))))

(define runtime-postlude
  (string-append
   (function-name '(six.identifier main))))

(define (comp-file path)
  (let ((ast (call-with-input-file path read-six)))
    (comp-program ast)))

(define (read-six port)
  (##six-types-set! '((void . #f) (char . #f) (int . #f)))
  (let ((rt (input-port-readtable port)))
    (input-port-readtable-set! port (readtable-start-syntax-set rt 'six))
    (read-all port)))

(define (main . args)
  (for-each comp-file args))

;; Example:
;;
;; $ gsi six-cc.scm winter-pi2.c > winter-pi2.sh ; time dash winter-pi2.sh
;; 31415926535897932384626433832795028841971693993751058209749445923078164062862089986280348253421170679821480865132823066470938446095505822317253594081284811174502841027019385211055596446229489549303819644288109756659334461284756482337867831652712019091456485669234603486104543266482133936072602491412737245870066063155881748815209209628292540917153643678925903600113305305488204665213841469519415116094330572703657595919530921861173819326117931051185480744623799627495673518857527248912279381830119491298336733624406566430860213949463952247371907021798609437027705392171762931767523846748184676694051320005681271452635608277857713427577896091736371787214684409012249534301465495853710507922796892589235420199561121290219608640344181598136297747713099605187072113499999983729780499510597317328160963185
;;
;; real	0m2.394s
;; user	0m2.143s
;; sys	0m0.248s
;; $ cat winter-pi2.c
;; /* #include <stdio.h> */
;;
;; /* https://cs.uwaterloo.ca/~alopez-o/math-faq/mathtext/node12.html */
;;
;;
;; int r[2801];
;; int i;
;; int k;
;; int b;
;; int d;
;; int c = 0;
;;
;; int main() {
;;
;;     for (; i < 2800; i++) {
;; 	r[i] = 2000;
;;     }
;;     r[i] = 0;
;;
;;     for (k = 2800; k > 0; k = k - 14) {
;;
;; 	d = 0;
;;
;; 	i = k;
;; 	for (;;) {
;; 	    d = d + r[i] * 10000;
;; 	    b = 2 * i - 1;
;;
;; 	    r[i] = d % b;
;; 	    d = d / b;
;; 	    i--;
;; 	    if (i == 0) break;
;; 	    d = d * i;
;; 	}
;;         putchar(48 + (c + d / 10000) / 1000 % 10);
;;         putchar(48 + (c + d / 10000) / 100 % 10);
;;         putchar(48 + (c + d / 10000) / 10 % 10);
;;         putchar(48 + (c + d / 10000) % 10);
;; 	c = d % 10000;
;;     }
;;
;;     putchar(10);
;;
;;     return 0;
;; }
