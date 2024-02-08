# update all the nnf dependencies on master
go get github.com/DataWorkflowServices/dws@master
go get github.com/NearNodeFlash/lustre-fs-operator@master
go get github.com/NearNodeFlash/nnf-sos@master
go get github.com/NearNodeFlash/nnf-dm@master
go mod tidy
