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

package internal

import (
	"context"
	"fmt"
	"math/rand"
	"reflect"
	"runtime"
	"strings"
	"time"

	"sigs.k8s.io/controller-runtime/pkg/client"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"

	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/types"

	dwsv1alpha2 "github.com/DataWorkflowServices/dws/api/v1alpha2"
	"github.com/DataWorkflowServices/dws/utils/dwdparse"
)

// StateHandler defines a method that handles a particular state in the workflow
type StateHandler func(context.Context, client.Client, *dwsv1alpha2.Workflow)

func (t *T) Execute(ctx context.Context, k8sClient client.Client) {
	for _, fn := range []StateHandler{t.proposal, t.setup, t.dataIn, t.preRun, t.postRun, t.dataOut, t.teardown} {
		fn(ctx, k8sClient, t.workflow)

		if t.options.stopAfter != nil {
			fnName := runtime.FuncForPC(reflect.ValueOf(fn).Pointer()).Name() // This will return something like `full-import-path.(*T).Function-fm`
			fnName = fnName[strings.Index(fnName, "(*T).")+5 : len(fnName)-3] // Extract the function name
			state := dwsv1alpha2.WorkflowState(strings.Title(fnName))
			if state == t.options.stopAfter.state {
				break
			}
		}
	}
}

func (t *T) proposal(ctx context.Context, k8sClient client.Client, workflow *dwsv1alpha2.Workflow) {
	// We're not ready to advance out of proposal yet, but check for expected error
	if t.options.expectError != nil && t.options.expectError.state == dwsv1alpha2.StateProposal {
		By("Waiting for Error status")
		waitForError(ctx, k8sClient, workflow, dwsv1alpha2.StateProposal)
		return
	}

	waitForReady(ctx, k8sClient, workflow, dwsv1alpha2.StateProposal)
}

func (t *T) setup(ctx context.Context, k8sClient client.Client, workflow *dwsv1alpha2.Workflow) {

	systemConfig := GetSystemConfiguraton(ctx, k8sClient)

	By("Assigns Computes")
	{
		// Assign Compute Resources (only if jobdw or persistentdw is present in workflow())
		// create_persistent & destroy_persistent do not need compute resources
		//Expect(directiveBreakdown.Status.Compute).NotTo(BeNil())
		computes := &dwsv1alpha2.Computes{}
		Expect(k8sClient.Get(ctx, ObjectKeyFromObjectReference(workflow.Status.Computes), computes)).To(Succeed())

		Expect(computes.Data).To(HaveLen(0))

		computes.Data = make([]dwsv1alpha2.ComputesData, 0)
		for _, node := range systemConfig.Spec.ComputeNodes {
			computes.Data = append(computes.Data, dwsv1alpha2.ComputesData{Name: node.Name})
			// TODO: Filter out unwanted compute nodes
		}

		Expect(k8sClient.Update(ctx, computes)).To(Succeed())
	}

	By("Assigns Servers")
	{
		for _, directiveBreakdownRef := range workflow.Status.DirectiveBreakdowns {
			directiveBreakdown := &dwsv1alpha2.DirectiveBreakdown{}
			Eventually(func(g Gomega) bool {
				g.Expect(k8sClient.Get(ctx, ObjectKeyFromObjectReference(directiveBreakdownRef), directiveBreakdown)).To(Succeed())
				return directiveBreakdown.Status.Ready
			}).Should(BeTrue())

			// persistentdw directives do not have StorageBreakdowns (Status.Storage)
			args, _ := dwdparse.BuildArgsMap(directiveBreakdown.Spec.Directive)
			if args["command"] == "persistentdw" {
				Expect(directiveBreakdown.Status.Storage).To(BeNil())
				continue
			}

			Expect(directiveBreakdown.Status.Storage).NotTo(BeNil())
			Expect(directiveBreakdown.Status.Storage.AllocationSets).NotTo(BeEmpty())

			servers := &dwsv1alpha2.Servers{}
			Expect(k8sClient.Get(ctx, ObjectKeyFromObjectReference(directiveBreakdown.Status.Storage.Reference), servers)).To(Succeed())
			Expect(servers.Spec.AllocationSets).To(BeEmpty())

			// Copy the allocation sets from the directive breakdown to the servers resource, assigning servers
			// as storage resources as necessary.

			// TODO We should assign storage nodes based on the current capabilities of the system and the label. For simple file systems
			// like XFS and GFS2, we can use any Rabbit. But for Lustre, we have to watch where we land the MDT/MGT, and ensure those are
			// exclusive to the Rabbit nodes.
			findStorageServers := func(set *dwsv1alpha2.StorageAllocationSet) []dwsv1alpha2.ServersSpecStorage {
				switch set.AllocationStrategy {
				case dwsv1alpha2.AllocatePerCompute:
					// Make one allocation per compute node
					storages := make([]dwsv1alpha2.ServersSpecStorage, len(systemConfig.Spec.StorageNodes))
					for index, node := range systemConfig.Spec.StorageNodes {
						storages[index].Name = node.Name
						storages[index].AllocationCount = len(node.ComputesAccess)
					}
					return storages
				case dwsv1alpha2.AllocateAcrossServers:
					// Make one allocation per Rabbit
					storages := make([]dwsv1alpha2.ServersSpecStorage, len(systemConfig.Spec.StorageNodes))
					for index, node := range systemConfig.Spec.StorageNodes {
						storages[index].Name = node.Name
						storages[index].AllocationCount = 1
					}
					return storages
				case dwsv1alpha2.AllocateSingleServer:
					// Make one allocation total
					storages := make([]dwsv1alpha2.ServersSpecStorage, 1)
					storages[0].Name = systemConfig.Spec.StorageNodes[rand.Intn(len(systemConfig.Spec.StorageNodes))].Name
					storages[0].AllocationCount = 1
					return storages
				}

				return []dwsv1alpha2.ServersSpecStorage{}
			}

			servers.Spec.AllocationSets = make([]dwsv1alpha2.ServersSpecAllocationSet, len(directiveBreakdown.Status.Storage.AllocationSets))
			for index, allocationSet := range directiveBreakdown.Status.Storage.AllocationSets {
				servers.Spec.AllocationSets[index] = dwsv1alpha2.ServersSpecAllocationSet{
					AllocationSize: allocationSet.MinimumCapacity,
					Label:          allocationSet.Label,
					Storage:        findStorageServers(&allocationSet),
				}
			}

			// TODO: If Lustre - we need to identify the MGT and MDT nodes (and combine them if necessary); and we
			//       can't colocate MGT nodes with other lustre's that might be in test.
			//       OST nodes can go anywhere

			Expect(k8sClient.Update(ctx, servers)).To(Succeed())
		}
	}

	t.AdvanceStateAndWaitForReady(ctx, k8sClient, workflow, dwsv1alpha2.StateSetup)
}

func (t *T) dataIn(ctx context.Context, k8sClient client.Client, workflow *dwsv1alpha2.Workflow) {
	t.AdvanceStateAndWaitForReady(ctx, k8sClient, workflow, dwsv1alpha2.StateDataIn)
}

func (t *T) preRun(ctx context.Context, k8sClient client.Client, workflow *dwsv1alpha2.Workflow) {
	t.AdvanceStateAndWaitForReady(ctx, k8sClient, workflow, dwsv1alpha2.StatePreRun)
}

func (t *T) postRun(ctx context.Context, k8sClient client.Client, workflow *dwsv1alpha2.Workflow) {
	t.AdvanceStateAndWaitForReady(ctx, k8sClient, workflow, dwsv1alpha2.StatePostRun)
}

func (t *T) dataOut(ctx context.Context, k8sClient client.Client, workflow *dwsv1alpha2.Workflow) {
	t.AdvanceStateAndWaitForReady(ctx, k8sClient, workflow, dwsv1alpha2.StateDataOut)

	// If copy_out directive was set, verify that the copy_in file matches the copy_out file on global lustre
	if t.options.globalLustre != nil && len(t.options.globalLustre.out) > 0 {
		VerifyCopyOut(ctx, k8sClient, t, t.options)
	}
}

func (t *T) teardown(ctx context.Context, k8sClient client.Client, workflow *dwsv1alpha2.Workflow) {
	t.AdvanceStateAndWaitForReady(ctx, k8sClient, workflow, dwsv1alpha2.StateTeardown)
}

func (t *T) AdvanceStateAndWaitForReady(ctx context.Context, k8sClient client.Client, workflow *dwsv1alpha2.Workflow, state dwsv1alpha2.WorkflowState) {
	By(fmt.Sprintf("Advances to %s State", state))

	// Set the desired State
	Eventually(func() error {
		Expect(k8sClient.Get(ctx, client.ObjectKeyFromObject(workflow), workflow)).Should(Succeed())
		workflow.Spec.DesiredState = state
		return k8sClient.Update(ctx, workflow)
	}).Should(Succeed(), fmt.Sprintf("updates state to '%s'", state))

	// If expecting an Error in this state, check for that instead
	if t.options.expectError != nil && t.options.expectError.state == state {
		By("Waiting for Error status")
		waitForError(ctx, k8sClient, workflow, state)
		return
	}

	waitForReady(ctx, k8sClient, workflow, state)
}

// Timeouts can be one of two configurable values passed into the context: lowTimeout and
// highTimeout. The lowTimeout is the default value used for states. highTimeout is used for any
// state that needs more time (e.g. Setup and Teardown) and is also configurable.
func getTimeout(ctx context.Context, state dwsv1alpha2.WorkflowState) time.Duration {

	// Retrieve the list of states that use highTimeout
	highTimeoutStates, ok := ctx.Value("highTimeoutStates").([]dwsv1alpha2.WorkflowState)
	if !ok {
		panic("could not retrieve highTimeoutStates from context")
	}

	// See if the current state is one of the high timeout states. If so, use highTimeout.
	for _, s := range highTimeoutStates {
		if state == s {
			t, ok := ctx.Value("highTimeout").(time.Duration)
			if !ok {
				panic("could not retrieve highTimeout from context")
			}
			return t
		}
	}

	// Otherwise, retrieve and use the lowTimeout
	t, ok := ctx.Value("lowTimeout").(time.Duration)
	if !ok {
		panic("could not retrieve lowTimeout from context")
	}
	return t
}

func waitForReady(ctx context.Context, k8sClient client.Client, workflow *dwsv1alpha2.Workflow, state dwsv1alpha2.WorkflowState) {

	achieveState := func(state dwsv1alpha2.WorkflowState) OmegaMatcher {
		return And(
			HaveField("Ready", BeTrue()),
			HaveField("State", Equal(state)),
			HaveField("Status", Equal(dwsv1alpha2.StatusCompleted)),
		)
	}

	// Get the timeout based on which state it is
	timeout := getTimeout(ctx, state)

	Eventually(func() dwsv1alpha2.WorkflowStatus {
		Expect(k8sClient.Get(ctx, client.ObjectKeyFromObject(workflow), workflow)).Should(Succeed())
		return workflow.Status
	}).
		WithTimeout(timeout).
		WithPolling(time.Second).
		Should(achieveState(state), fmt.Sprintf("achieve state '%s'", state))
}

func waitForError(ctx context.Context, k8sClient client.Client, workflow *dwsv1alpha2.Workflow, state dwsv1alpha2.WorkflowState) {
	achieveState := func(state dwsv1alpha2.WorkflowState) OmegaMatcher {
		return And(
			HaveField("Ready", BeFalse()),
			HaveField("State", Equal(state)),
			HaveField("Status", Equal(dwsv1alpha2.StatusError)),
		)
	}

	By("Expect an Error Status")
	Eventually(func() dwsv1alpha2.WorkflowStatus {
		Expect(k8sClient.Get(ctx, client.ObjectKeyFromObject(workflow), workflow)).Should(Succeed())
		return workflow.Status
	}).
		WithTimeout(time.Minute).
		WithPolling(time.Second).
		Should(achieveState(state), fmt.Sprintf("error in state '%s'", state))
}

func ObjectKeyFromObjectReference(r corev1.ObjectReference) types.NamespacedName {
	return types.NamespacedName{Name: r.Name, Namespace: r.Namespace}
}
