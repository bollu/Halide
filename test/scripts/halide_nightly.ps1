# Get unix-style date in the path
$env:PATH += ";C:\Program Files (x86)\Git\bin"

$Date = date +%Y_%m_%d
$Log = "E:\Code\Halide\test\scripts\testlog.txt"

cd E:\Code\Halide\test\scripts

git pull
git checkout master

.\distrib_windows.ps1 | tee $Log

cd E:\Code\Halide\distrib

$Failed = $LastExitCode
if ($Failed) {
  $LogName = "logs_Windows_FAIL_" + $Date + ".txt"
} else {
  $LogName = "logs_Windows_PASS_" + $Date + ".txt"
}

move ${Log} ${LogName}

copy *${Date}.zip "E:\Google Drive\Halide_Binaries_Windows"
copy ${LogName} "E:\Google Drive\Halide_Binaries_Windows"