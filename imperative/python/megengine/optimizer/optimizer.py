# -*- coding: utf-8 -*-
# MegEngine is Licensed under the Apache License, Version 2.0 (the "License")
#
# Copyright (c) 2014-2020 Megvii Inc. All rights reserved.
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT ARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
from abc import ABCMeta, abstractmethod
from collections.abc import Iterable
from contextlib import contextmanager
from typing import Dict
from typing import Iterable as Iter
from typing import Union

import numpy as np

from ..tensor import Parameter, Tensor


class _RequiredParameter:
    def __repr__(self):
        return "<required parameter>"


required = _RequiredParameter()


class Optimizer(metaclass=ABCMeta):
    r"""Base class for all optimizers.

    :param params: specifies what Tensors should be optimized.
    :param defaults: a dict of default parameters of Optimizer, like learning rate or momentum.
    """

    def __init__(  # pylint: disable=too-many-branches
        self, params: Union[Iter[Parameter], dict], defaults: dict,
    ):
        self._state = dict()
        self._defaults = defaults

        if isinstance(params, (Parameter, dict)):
            params = [params]
        else:
            if not isinstance(params, Iterable):
                raise TypeError(
                    "params argument given to the optimizer should be "
                    "Parameter or dict, or Iterable of them"
                )

        self.param_groups = []  # type: list

        param_groups = list(params)
        if len(param_groups) == 0:
            raise ValueError("optimizer got an empty parameter list")

        param_type = type(param_groups[0])
        for param in param_groups:
            if not isinstance(param, param_type):
                raise TypeError(
                    "types of params argument given to the optimizer shoud be same"
                )

        if not isinstance(param_groups[0], dict):
            param_groups = [{"params": param_groups}]

        for group in param_groups:
            self.add_param_group(group)

        for group in self.param_groups:
            self._create_state(group)

    def add_param_group(self, param_group: dict):
        r"""Add a param group to ``param_groups`` of the :class:`~megengine.optim.optimizer.Optimizer`.

        This can be useful when fine tuning a pre-trained network as frozen layers can be made
        trainable and added to the :class:`~megengine.optim.optimizer.Optimizer` as training progresses.

        :param param_group: specifies what tensors should be optimized along with group.

        """
        assert isinstance(param_group, dict), "param group must be a dict"

        if isinstance(param_group["params"], Parameter):
            param_group["params"] = [param_group["params"]]
        else:
            param_group["params"] = list(param_group["params"])

        for param in param_group["params"]:
            if not isinstance(param, Parameter):
                raise TypeError(
                    "optimizer can only optimize Parameters, but one of the params is "
                    + type(param)
                )

        for name, default in self._defaults.items():
            if default is required and name not in param_group:
                raise ValueError(
                    "parameter group didn't specify a value of "
                    "required optimization parameter " + name
                )
            param_group.setdefault(name, default)

        param_set = set()

        for group in self.param_groups:
            param_set.update(set(map(id, group["params"])))

        assert param_set.isdisjoint(
            set(map(id, param_group["params"]))
        ), "some parameters appear in more than one parameter group"

        self.param_groups.append(param_group)

    def _add_state(self, param, state_name, initializer=None):
        if initializer is None:
            initializer = np.zeros(param.shape, dtype=np.float32)
        state_dict = self._state.setdefault(param, {})
        assert state_name not in state_dict
        state = Tensor(initializer)
        state_dict[state_name] = state

    @abstractmethod
    def _create_state(self, param_group):
        pass

    @abstractmethod
    def _updates(self, param_group):
        pass

    def _get_params(self):
        params = []
        for group in self.param_groups:
            for param in group["params"]:
                params.append(param)
        return params

    def step(self):
        r"""Performs a single optimization step.

        """
        for group in self.param_groups:
            if isinstance(group["params"], set):
                raise TypeError(
                    "optimized parameters need to be organized in ordered collections, "
                    "but the ordering of parameters in sets will change between runs. "
                    "Please use a list instead."
                )
            self._updates(group)
        return self

    def clear_grad(self):
        r"""Clear the grad buffer.

        """
        for param_group in self.param_groups:
            for param in param_group["params"]:
                param.grad = None

    def state_dict(self) -> Dict:
        r"""Export the optimizer state.

        :return: optimizer state. Can be loaded by :meth:`load_state_dict`.
        """
        param_groups = []
        state = dict()
        param2id = dict()

        cur_id = 0
        for group in self.param_groups:
            for param in group["params"]:
                if param not in param2id:
                    param2id[param] = cur_id
                    cur_id += 1

        for param, st in self._state.items():
            state[param2id[param]] = st

        for group in self.param_groups:
            param_group = {k: v for k, v in group.items() if k != "params"}
            param_group["params"] = [param2id[param] for param in group["params"]]
            param_groups.append(param_group)

        return {"param_groups": param_groups, "state": state}

    def load_state_dict(self, state: dict):
        r"""Loads the optimizer state.

        :param state: optimizer state. Should be an object returned
                from a call to :meth:`state_dict`.
        """
        if len(self.param_groups) != len(state["param_groups"]):
            raise ValueError(
                "loaded state dict has a different number of parameter groups"
            )
        parameter_map = dict()  # type: Dict
        for group_new, group_saved in zip(self.param_groups, state["param_groups"]):
            if len(group_new["params"]) != len(group_saved["params"]):
                raise ValueError(
                    "loaded state dict contains a parameter group that "
                    "doesn't match the size of optimizer's group"
                )
            for param_new, param_saved in zip(
                group_new["params"], group_saved["params"]
            ):
                p = param_new
                self._state[p] = state["state"][param_saved].copy()
                for k, v in self._state[p].items():
                    if isinstance(v, Tensor):
                        # TODO: maybe a more efficient way?
                        self._state[p][k] = Tensor(v.numpy())

            if set(group_new.keys()) != set(group_saved.keys()):
                raise ValueError(
                    "loaded state dict contains a parameter group that "
                    "doesn't match the keys of optimizer's group"
                )
            for key in group_new.keys():
                if key != "params":
                    group_new[key] = group_saved[key]

        if len(self._state.keys()) != len(state["state"].keys()):
            raise ValueError(
                "loaded state dict contains a state that doesn't match "
                "the size of optimizer's state"
            )
