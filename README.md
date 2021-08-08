
# EMR integration with Apache Ranger 

Apache Ranger 是一个用于在整个 Hadoop 平台上启用、监控和管理全面的数据安全性的框架。

利用 Apache Ranger 可以实现：
 - 集中安全管理以在中央 UI 或使用 REST API 管理所有与安全相关的任务
 - 使用 Hadoop 组件/工具执行特定操作，通过中央管理工具进行管理的细粒度授权
 - 跨 Hadoop 生态组件标准化授权方法
 - 增强对不同授权方法的支持 - 基于角色的访问控制、基于属性的访问控制等。
 - 在 Hadoop 的所有组件中集中审核用户访问和管理操作

Amazon EMR 是行业领先的云大数据平台，可使用多种开放源代码工具处理大量数据，例如 Apache Spark、Apache Hive、Apache HBase、Apache Flink、Apache Hudi 和 Presto。Amazon EMR 通过自动执行耗时的任务（例如，预置容量和调优集群），可以轻松地设置、操作和扩展大数据环境。

下面内容是如何部署 Apache Ranger，对 Amazon EMR 中 Hive，Presto，Spark 数据分析应用组件，进行基于 DB/Table/Column 资源级别 ，USE/SELECT/DELETE 等操作行为级别的精细化权限控制和审计，包括详细步骤和自动化脚本。

具体内容分为：

| Index       				| Ranger Version | EMR Version 	| Supported Application |
| ----------- 				| -----------    | -----------    | -----------    	    |
| [EMR 5.x + Apache Ranger](./Ranger2.X-EMR5.X)   | Ranger 2.0/2.1 | EMR 5.30+      | Hive2, Prestodb, Hue	 |
| [EMR 6.x + Apache Ranger](./Ranger2.X-EMR6.X)  	| Ranger 2.1.1   | EMR 6.1+      | Hive3, PrestoSQL, Hue   |
| [EMR 5.x Managed Ranger](https://github.com/hxhwing/EMR-Managed-Ranger-Plugin) 	| Ranger 2.1   | EMR 6.1+      | Hive2, Spark, S3   	  |

