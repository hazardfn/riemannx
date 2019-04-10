Application.ensure_all_started(:propcheck)

{:ok, cwd} = File.cwd()

System.cmd("sh", ["#{cwd}/test/gen_cert.sh"])

ExUnit.start()

File.rm_rf!("#{cwd}/test/certs/client/*")
File.rm_rf!("#{cwd}/test/certs/server/*")
File.rm_rf!("#{cwd}/test/certs/testca/*")
