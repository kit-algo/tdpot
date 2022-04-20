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
sizes = [int(f) for f in os.listdir(base + 'compression')]
datasets = { num: [json.load(open(path)) for path in glob.glob(base + f"compression/{num}/*.json") + glob.glob(base + f"compression_1h/{num}/*.json")] for num in sizes }

queries = pd.DataFrame.from_records([{
    **algo,
    'potential': run['potential'],
    'graph': run['args'][1],
    'queryset': run['args'][2],
    'num_metrics': num_metrics,
} for (num_metrics, data) in datasets.items() for run in data for algo in run['algo_runs']])

paths = glob.glob(base + "rand/*.json") + glob.glob(base + "1h/*.json")
data = [json.load(open(path)) for path in paths]
queries_uncompressed = pd.DataFrame.from_records([{
    **algo,
    'potential': run['potential'],
    'graph': run['args'][1],
    'queryset': run['args'][2],
    'topo': 'no_topo' not in run['program'],
} for run in data for algo in run['algo_runs']]).query('topo')

merged = queries.merge(queries_uncompressed, how='left', on=['graph', 'potential', 'from', 'to', 'at'], suffixes=[None, '_uncompressed'])
merged['slowdown'] = merged['running_time_ms'] / merged['running_time_ms_uncompressed']
merged['potential'] = merged['potential'].map({ 'multi_metric_pot': 'MMP', 'interval_min_pot': 'IMP' })
merged['queryset'] = merged['queryset'].map({ 'queries/uniform': 'Random', 'queries/1h': '1h' })
merged = merged.rename(columns={ 'queryset': 'Queries', 'potential': 'Potential' })

queries_sub = merged.loc[lambda x: x['graph'].str.contains('osm') & (x['num_metrics'] % 10 != 0)]
queries_sub

fig, axs = plt.subplots(1, 2, figsize=(11,4))
g = sns.lineplot(data=queries_sub, x='num_metrics', y='running_time_ms', hue='Potential', style='Queries', ax=axs[0], ci=None, palette=['C1', 'C2'], hue_order=['MMP', 'IMP'], markers=True)
g.set_yscale('log')
g.set_ylabel('Running time [ms]')
g.set_xlabel('# Weight Functions')
g.yaxis.set_major_formatter(mpl.ticker.FuncFormatter(lambda val, pos: f"{val if val < 1.0 else int(val)}"))
g.grid(True, which="minor", linewidth=0.6)

g = sns.boxplot(data=queries_sub, x='num_metrics', y='slowdown', hue='Potential', ax=axs[1], palette=['C1', 'C2'], hue_order=['MMP', 'IMP'], linewidth=0.8, flierprops=dict(marker='o', markerfacecolor='none', markeredgewidth=0.3))
g.set_yscale('log')
g.set_ylabel('Slowdown over Uncompressed')
g.set_xlabel('# Weight Functions')
g.yaxis.set_major_formatter(mpl.ticker.FuncFormatter(lambda val, pos: f"{val if val < 1.0 else int(val)}"))
g.grid(True, which="minor", linewidth=0.6)
handles, labels = g.get_legend_handles_labels()
g.legend(handles=handles, labels=['MMP', 'IMP'])

plt.tight_layout()
g.get_figure().savefig('paper/fig/compression.pdf')
