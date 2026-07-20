#include <tcl.h>
#include <stdio.h>
int main(int argc, char **argv) {
    Tcl_FindExecutable(argv[0]);
    Tcl_Interp *interp = Tcl_CreateInterp();
    if (!interp) { printf("FAIL: no interp\n"); return 1; }
    printf("patchlevel=%s\n", Tcl_GetVar(interp, "tcl_patchLevel", TCL_GLOBAL_ONLY));
    if (Tcl_Eval(interp, "expr {6*7}") == TCL_OK)
        printf("expr 6*7 = %s\n", Tcl_GetStringResult(interp));
    else printf("FAIL expr: %s\n", Tcl_GetStringResult(interp));
    if (Tcl_Eval(interp, "string toupper {tcl nine on android}") == TCL_OK)
        printf("string = %s\n", Tcl_GetStringResult(interp));
    if (Tcl_Eval(interp, "expr {2**64}") == TCL_OK)  /* bignum -> libtommath */
        printf("bignum 2**64 = %s\n", Tcl_GetStringResult(interp));
    printf("OK: Tcl %s interp live on Android\n", Tcl_GetVar(interp,"tcl_version",TCL_GLOBAL_ONLY));
    return 0;
}
