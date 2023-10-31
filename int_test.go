/*
 * Copyright 2023 Hewlett Packard Enterprise Development LP
 * Other additional copyright holders may be indicated within.
 *
 * The entirety of this work is licensed under the Apache License,
 * Version 2.0 (the "License"); you may not use this file except
 * in compliance with the License.
 *
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package test

import (
	"fmt"

	. "github.com/NearNodeFlash/nnf-integration-test/internal"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
	"go.openly.dev/pointy"

	dwsv1alpha2 "github.com/DataWorkflowServices/dws/api/v1alpha2"
)

var tests = []*T{
	// Examples:
	//
	// Mark a test case as Focused(). Ginkgo will only run tests that have the Focus decorator.
	//   MakeTest("Focused", "#DW ...").Focused(),
	//
	// Mark a test case as Pending(). Ginkgo will not run any tests that have the Pending decorator
	//   MakeTest("Pending", "#DW ...").Pending()
	//
	// Mark a test case so it will stop after the workflow achieves the desired state of PreRun
	//   MakeTest("Stop After", "#DW ...").StopAfter(wsv1alpha1.StatePreRun),
	//
	// Duplicate a test case 20 times.
	//   DuplicateTest(
	//      MakeTest("XFS", "#DW jobdw type=xfs name=xfs capacity=1TB"),
	//      20,
	//   ),

	MakeTest("XFS", "#DW jobdw type=xfs name=xfs capacity=1TB").WithLabels(Simple),
	MakeTest("GFS2", "#DW jobdw type=gfs2 name=gfs2 capacity=1TB").WithLabels(Simple),
	MakeTest("Lustre", "#DW jobdw type=lustre name=lustre capacity=1TB").WithLabels(Simple),
	MakeTest("Raw", "#DW jobdw type=raw name=raw capacity=1TB").WithLabels(Simple),

	// DuplicateTest(
	// 	MakeTest("XFS", "#DW jobdw type=xfs name=xfs capacity=1TB").Pending(), // Will fail for Setup() exceeding time limit; needs investigation
	// 	5,
	// ),

	// Storage Profiles
	MakeTest("XFS with Storage Profile",
		"#DW jobdw type=xfs name=xfs-storage-profile capacity=1TB profile=my-xfs-storage-profile").
		WithStorageProfile(),
	MakeTest("GFS2 with Storage Profile",
		"#DW jobdw type=gfs2 name=gfs2-storage-profile capacity=1TB profile=my-gfs2-storage-profile").
		WithStorageProfile(),

	// Persistent
	MakeTest("Persistent Lustre",
		"#DW create_persistent type=lustre name=persistent-lustre capacity=1TB").
		AndCleanupPersistentInstance().
		Serialized(),

	// Data Movement
	MakeTest("XFS with Data Movement",
		"#DW jobdw type=xfs name=xfs-data-movement capacity=1TB",
		"#DW copy_in source=/lus/global/testuser/test.in destination=$DW_JOB_xfs-data-movement/",
		"#DW copy_out source=$DW_JOB_xfs-data-movement/test.in destination=/lus/global/testuser/test.out").
		WithPersistentLustre("xfs-data-movement-lustre-instance").
		WithGlobalLustreFromPersistentLustre("global", []string{"default"}).
		HardwareRequired(),

	// Containers - MPI
	MakeTest("GFS2 with MPI Containers",
		"#DW jobdw type=gfs2 name=gfs2-with-containers-mpi capacity=100GB",
		"#DW container name=gfs2-with-containers-mpi profile=example-mpi "+
			"DW_JOB_foo_local_storage=gfs2-with-containers-mpi").
		WithPermissions(1050, 1051).WithLabels("mpi"),
	MakeTest("Lustre with MPI Containers",
		"#DW jobdw type=lustre name=lustre-with-containers-mpi capacity=100GB",
		"#DW container name=lustre-with-containers-mpi profile=example-mpi "+
			"DW_JOB_foo_local_storage=lustre-with-containers-mpi").
		WithPermissions(1050, 1051).WithLabels("mpi"),
	MakeTest("GFS2 and Global Lustre with MPI Containers",
		"#DW jobdw type=gfs2 name=gfs2-and-global-with-containers-mpi capacity=100GB",
		"#DW container name=gfs2-and-global-with-containers-mpi profile=example-mpi "+
			"DW_JOB_foo_local_storage=gfs2-and-global-with-containers-mpi "+
			"DW_GLOBAL_foo_global_lustre=/lus/sawbill").
		WithPermissions(1050, 1051).
		WithPersistentLustre("gfs2-and-global-with-containers-mpi-sawbill").
		WithGlobalLustreFromPersistentLustre("sawbill", []string{"default"}).
		WithLabels("mpi", "global-lustre"),

	// Containers - MPI failures
	MakeTest("PreRun timeout on MPI containers",
		"#DW container name=prerun-timeout-mpi profile=example-mpi-prerun-timeout").
		WithPermissions(1050, 1051).WithLabels("mpi", "timeout").
		WithContainerProfile("example-mpi", &ContainerProfileOptions{PrerunTimeoutSeconds: pointy.Int(1), NoStorage: true}).
		ExpectError(dwsv1alpha2.StatePreRun),
	MakeTest("PostRun timeout on MPI containers",
		"#DW container name=postrun-timeout-mpi profile=example-mpi-postrun-timeout").
		WithPermissions(1050, 1051).WithLabels("mpi", "timeout").
		WithContainerProfile("example-mpi-webserver", &ContainerProfileOptions{PostrunTimeoutSeconds: pointy.Int(1), NoStorage: true}).
		ExpectError(dwsv1alpha2.StatePostRun),
	MakeTest("Non-zero exit on MPI containers",
		"#DW container name=mpi-container-fail profile=example-mpi-fail-noretry").
		WithPermissions(1050, 1051).WithLabels("mpi", "fail").
		WithContainerProfile("example-mpi-fail", &ContainerProfileOptions{RetryLimit: pointy.Int(0)}).
		ExpectError(dwsv1alpha2.StatePostRun),

	// Containers - Non-MPI
	MakeTest("GFS2 with Containers",
		"#DW jobdw type=gfs2 name=gfs2-with-containers capacity=100GB",
		"#DW container name=gfs2-with-containers profile=example-success DW_JOB_foo_local_storage=gfs2-with-containers").
		WithPermissions(1050, 1051).WithLabels("non-mpi"),
	MakeTest("GFS2 and Global Lustre with Containers",
		"#DW jobdw type=gfs2 name=gfs2-and-global-with-containers capacity=100GB",
		"#DW container name=gfs2-and-global-with-containers profile=example-success "+
			"DW_JOB_foo_local_storage=gfs2-and-global-with-containers "+
			"DW_GLOBAL_foo_global_lustre=/lus/cherokee").
		WithPermissions(1050, 1051).
		WithPersistentLustre("gfs2-and-global-with-containers-cherokee").
		WithGlobalLustreFromPersistentLustre("cherokee", []string{"default"}).
		WithLabels("non-mpi", "global-lustre"),

	// Containers - Non-MPI failures
	MakeTest("PreRun timeout on non-MPI containers",
		"#DW container name=prerun-timeout profile=example-prerun-timeout").
		WithPermissions(1050, 1051).WithLabels("non-mpi", "timeout").
		WithContainerProfile("example-forever", &ContainerProfileOptions{PrerunTimeoutSeconds: pointy.Int(1), NoStorage: true}).
		ExpectError(dwsv1alpha2.StatePreRun),
	MakeTest("PostRun timeout on non-MPI containers",
		"#DW container name=postrun-timeout profile=example-postrun-timeout").
		WithPermissions(1050, 1051).WithLabels("non-mpi", "timeout").
		WithContainerProfile("example-forever", &ContainerProfileOptions{PostrunTimeoutSeconds: pointy.Int(1), NoStorage: true}).
		ExpectError(dwsv1alpha2.StatePostRun),
	MakeTest("Non-zero exit on non-MPI containers",
		"#DW container name=container-fail profile=example-fail-noretry").
		WithPermissions(1050, 1051).WithLabels("non-mpi", "fail").
		WithContainerProfile("example-fail", &ContainerProfileOptions{RetryLimit: pointy.Int(0)}).
		ExpectError(dwsv1alpha2.StatePostRun),

	// Containers - Unsupported Filesystems. These should fail as xfs/raw filesystems are not supported for containers.
	MakeTest("XFS with Containers",
		"#DW jobdw type=xfs name=xfs-with-containers capacity=100GB",
		"#DW container name=xfs-with-containers profile=example-success DW_JOB_foo_local_storage=xfs-with-containers").
		ExpectError(dwsv1alpha2.StateProposal).WithLabels("unsupported-fs"),
	MakeTest("Raw with Containers",
		"#DW jobdw type=raw name=raw-with-containers capacity=100GB",
		"#DW container name=raw-with-containers profile=example-success DW_JOB_foo_local_storage=raw-with-containers").
		ExpectError(dwsv1alpha2.StateProposal).WithLabels("unsupported-fs"),

	// Containers - Multiple Storages
	MakeTest("GFS2 and Lustre with Containers",
		"#DW jobdw name=containers-local-storage type=gfs2 capacity=100GB",
		"#DW persistentdw name=containers-persistent-storage",
		"#DW container name=gfs2-lustre-with-containers profile=example-success DW_JOB_foo_local_storage=containers-local-storage DW_PERSISTENT_foo_persistent_storage=containers-persistent-storage").
		WithPersistentLustre("containers-persistent-storage").
		WithPermissions(1050, 1051).
		WithLabels("multi-storage"),
	MakeTest("GFS2 and Lustre with Containers MPI",
		"#DW jobdw name=containers-local-storage-mpi type=gfs2 capacity=100GB",
		"#DW persistentdw name=containers-persistent-storage-mpi",
		"#DW container name=gfs2-lustre-with-containers-mpi profile=example-mpi DW_JOB_foo_local_storage=containers-local-storage-mpi DW_PERSISTENT_foo_persistent_storage=containers-persistent-storage-mpi").
		WithPersistentLustre("containers-persistent-storage-mpi").
		WithPermissions(1050, 1051).
		WithLabels("multi-storage"),

	// External MGS
	MakeTest("Lustre with MGS pool",
		"#DW jobdw name=external-mgs-pool type=lustre capacity=100GB profile=example-external-mgs").
		WithMgsPool("lustre-mgs-pool", 1).WithStorageProfileExternalMGS("pool:lustre-mgs-pool"),
}

var _ = Describe("NNF Integration Test", func() {

	iterator := TestIterator(tests)
	for t := iterator.Next(); t != nil; t = iterator.Next() {

		// Note that you must assign a copy of the loop variable to a local variable - otherwise
		// the closure will capture the mutating loop variable and all the specs will run against
		// the last element in the loop. It is idiomatic to give the local copy the same name as
		// the loop variable.
		t := t

		Describe(t.Name(), append(t.Args(), func() {

			// Prepare any necessary test conditions prior to creating the workflow
			BeforeEach(func() {
				Expect(t.Prepare(ctx, k8sClient)).To(Succeed())
				DeferCleanup(func() { Expect(t.Cleanup(ctx, k8sClient)).To(Succeed()) })
			})

			// Create the workflow and delete it on cleanup
			BeforeEach(func() {
				workflow := t.Workflow()

				By(fmt.Sprintf("Creating workflow '%s'", workflow.Name))
				Expect(k8sClient.Create(ctx, workflow)).To(Succeed())

				DeferCleanup(func(context SpecContext) {
					if t.ShouldTeardown() {
						// TODO: Ginkgo's `--fail-fast` option still seems to execute DeferCleanup() calls
						//       See if this is by design or if we might need to move this to an AfterEach()
						if !context.SpecReport().Failed() {
							t.AdvanceStateAndWaitForReady(ctx, k8sClient, workflow, dwsv1alpha2.StateTeardown)

							Expect(k8sClient.Delete(ctx, workflow)).To(Succeed())
						}
					}
				})
			})

			// Report additional workflow data for each failed test
			ReportAfterEach(func(report SpecReport) {
				if report.Failed() {
					workflow := t.Workflow()
					AddReportEntry(fmt.Sprintf("Workflow '%s' Failed", workflow.Name), workflow.Status)
				}
			})

			// Run the workflow from Setup through Teardown
			It("Executes", func() { t.Execute(ctx, k8sClient) })

		})...)
	}
})
