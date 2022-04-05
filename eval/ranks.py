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
paths = glob.glob(base + "rank/*.json") + glob.glob(base + "rank_live/*.json")
data = [json.load(open(path)) for path in paths]

queries = pd.DataFrame.from_records([{
    **algo,
    'potential': run['potential'],
    'graph': run['args'][1],
    'metric': 'predicted' if run['program'] in ['predicted_queries', 'predicted_queries_no_topo'] else run['args'][3],
    'topo': 'no_topo' not in run['program']
} for run in data for algo in run['algo_runs']]).query('topo')

plt.figure(figsize=(11,5))
g = sns.boxplot(data=queries.loc[lambda x: x['graph'].str.contains('ptv')].query('metric == "live_data" & rank >= 10'), x='rank', y='running_time_ms', hue='potential',
                hue_order=['lower_bound_cch_pot', 'multi_metric_pot', 'interval_min_pot'],
                showmeans=False, linewidth=0.8, flierprops=dict(marker='o', markerfacecolor='none', markeredgewidth=0.3))
g.set_yscale('log')
handles, labels = g.get_legend_handles_labels()
g.legend(handles=handles, labels=['CCH Potential', 'MMP', 'IMP'])
g.set_ylabel('Running Time [ms]')
g.set_xlabel('Rank')
g.yaxis.set_major_locator(mpl.ticker.LogLocator(base=10,numticks=10))
g.yaxis.set_major_formatter(mpl.ticker.FuncFormatter(lambda val, pos: f"{val if val < 1.0 else int(val)}"))
g.xaxis.set_major_formatter(mpl.ticker.FuncFormatter(lambda val, pos: f"$2^{{{val+10}}}$")) # no idea why we dont get the val but the index here...
plt.tight_layout()
g.get_figure().savefig('paper/fig/ranks.pdf')
