#!/usr/bin/env python3

import numpy as np
import matplotlib as mpl
from matplotlib import pyplot as plt
import seaborn as sns
sns.set()

import pandas as pd

import json
import glob
import os
import re

base = "exp/"
paths = glob.glob(base + "rand/*.json") + glob.glob(base + "1h/*.json")
data = [json.load(open(path)) for path in paths]

queries = pd.DataFrame.from_records([{
    **algo,
    'potential': run['potential'],
    'graph': run['args'][1],
    'queryset': run['args'][2],
    'topo': 'no_topo' not in run['program'],
} for run in data for algo in run['algo_runs']])

queries_shifted = queries.copy()
queries_shifted['at'] += 24 * 3600 * 1000
queries = pd.concat([queries, queries_shifted], ignore_index=True)

queries = queries.query('topo')

queries['departure_hour'] = queries['at'] // 3600000
queries_sub = queries.query('potential != "zero"').loc[lambda x: x['graph'].str.contains('osm')]

fig, axs = plt.subplots(1, 2, figsize=(11,4))
g = sns.lineplot(data=queries_sub.query('queryset == "queries/uniform" & departure_hour <= 24'), x='departure_hour', y='running_time_ms', hue='potential', hue_order=['lower_bound_cch_pot', 'multi_metric_pot', 'interval_min_pot'], ax=axs[0], ci=None)
g.set_title('Uniform Queries')
g.set_xlabel('Departure')
g.set_ylabel('Running time [ms]')
g.xaxis.set_major_locator(mpl.ticker.IndexLocator(6,0))
g.xaxis.set_major_formatter(mpl.ticker.FuncFormatter(lambda val, pos: f"{int(val)}:00"))
g.legend(['CCH Potentials', 'MMP', 'IMP'], title=None, loc='upper right')
g = sns.lineplot(data=queries_sub.query('queryset == "queries/1h" & departure_hour <= 24'), x='departure_hour', y='running_time_ms', hue='potential', hue_order=['lower_bound_cch_pot', 'multi_metric_pot', 'interval_min_pot'], ax=axs[1], ci=None, legend=False)
g.set_title('1h Queries')
g.set_xlabel('Departure')
g.set_ylabel('Running time [ms]')
g.xaxis.set_major_locator(mpl.ticker.IndexLocator(6,0))
g.xaxis.set_major_formatter(mpl.ticker.FuncFormatter(lambda val, pos: f"{int(val)}:00"))

plt.tight_layout()
g.get_figure().savefig('paper/fig/perf_over_day.pdf')
