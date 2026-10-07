import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.*;
import ghidra.program.model.listing.*;
import java.io.*;
public class ExportDecompiled extends GhidraScript {
 public void run() throws Exception {
  DecompInterface d=new DecompInterface(); d.openProgram(currentProgram);
  int ok=0,failed=0;
  try(PrintWriter w=new PrintWriter(new File(getScriptArgs()[0]))) {
   w.println("/* Recovered pseudocode, not original source. */");
   FunctionIterator fs=currentProgram.getFunctionManager().getFunctions(true);
   while(fs.hasNext() && !monitor.isCancelled()) {
    Function f=fs.next(); if(f.isExternal()) continue;
    DecompileResults r=d.decompileFunction(f,30,monitor);
    w.println("\n/* "+f.getEntryPoint()+" "+f.getName()+" */");
    if(r.decompileCompleted() && r.getDecompiledFunction()!=null) {w.println(r.getDecompiledFunction().getC());ok++;}
    else {w.println("/* FAILED: "+r.getErrorMessage()+" */"); failed++;}
   }
  } finally {d.dispose();}
  println("EXPORT complete: "+ok+" functions, "+failed+" failures");
 }
}
