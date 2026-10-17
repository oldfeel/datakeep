/*
 * 内置示例名录（演示用，CC0）
 * 覆盖 6 个界 · 43 个门，每个门至少有 纲/目/科/属/种，保证树里没有空门。
 * 节点数组格式：[中文名, 学名, 子节点数组?]
 * 层级由 depth 自动决定：界 / 门 / 纲 / 目 / 科 / 属 / 种
 */
window.SAMPLE_TAXA = {
  version: 'sample-0.3.0',
  ladder: ['kingdom', 'phylum', 'class', 'order', 'family', 'genus', 'species'],
  tree: [
    /* ============ 动物界 · 13 个门 ============ */
    ['动物界', 'Animalia', [
      ['脊索动物门', 'Chordata', [
        ['哺乳纲', 'Mammalia', [
          ['食肉目', 'Carnivora', [
            ['猫科', 'Felidae', [
              ['豹属', 'Panthera', [['虎', 'Panthera tigris'], ['狮', 'Panthera leo'], ['雪豹', 'Panthera uncia']]],
              ['猫属', 'Felis', [['家猫', 'Felis catus']]],
            ]],
            ['犬科', 'Canidae', [
              ['犬属', 'Canis', [['灰狼', 'Canis lupus'], ['家犬', 'Canis lupus familiaris']]],
              ['狐属', 'Vulpes', [['赤狐', 'Vulpes vulpes']]],
            ]],
          ]],
          ['鲸偶蹄目', 'Cetartiodactyla', [
            ['牛科', 'Bovidae', [
              ['牛属', 'Bos', [['黄牛', 'Bos taurus']]],
              ['水牛属', 'Bubalus', [['水牛', 'Bubalus bubalis']]],
            ]],
            ['鹿科', 'Cervidae', [
              ['鹿属', 'Cervus', [['梅花鹿', 'Cervus nippon'], ['马鹿', 'Cervus elaphus']]],
            ]],
          ]],
        ]],
        ['鸟纲', 'Aves', [
          ['雀形目', 'Passeriformes', [
            ['鸦科', 'Corvidae', [
              ['鸦属', 'Corvus', [['大嘴乌鸦', 'Corvus macrorhynchos'], ['秃鼻乌鸦', 'Corvus frugilegus']]],
              ['鹊属', 'Pica', [['喜鹊', 'Pica pica']]],
            ]],
            ['雀科', 'Passeridae', [
              ['麻雀属', 'Passer', [['树麻雀', 'Passer montanus']]],
            ]],
          ]],
          ['鹰形目', 'Accipitriformes', [
            ['鹰科', 'Accipitridae', [
              ['雕属', 'Aquila', [['金雕', 'Aquila chrysaetos']]],
              ['鸢属', 'Milvus', [['黑鸢', 'Milvus migrans']]],
            ]],
          ]],
        ]],
        ['爬行纲', 'Reptilia', [
          ['有鳞目', 'Squamata', [
            ['游蛇科', 'Colubridae', [
              ['锦蛇属', 'Elaphe', [['黑眉锦蛇', 'Elaphe taeniura'], ['王锦蛇', 'Elaphe carinata']]],
            ]],
            ['蝰科', 'Viperidae', [
              ['蝮属', 'Gloydius', [['短尾蝮', 'Gloydius brevicaudus']]],
            ]],
          ]],
          ['龟鳖目', 'Testudines', [
            ['鳖科', 'Trionychidae', [
              ['鳖属', 'Pelodiscus', [['中华鳖', 'Pelodiscus sinensis']]],
            ]],
            ['陆龟科', 'Testudinidae', [
              ['象龟属', 'Chelonoidis', [['加拉帕戈斯象龟', 'Chelonoidis nigra']]],
            ]],
          ]],
        ]],
        ['两栖纲', 'Amphibia', [
          ['无尾目', 'Anura', [
            ['蛙科', 'Ranidae', [
              ['侧褶蛙属', 'Pelophylax', [['黑斑侧褶蛙', 'Pelophylax nigromaculatus']]],
            ]],
            ['蟾蜍科', 'Bufonidae', [
              ['蟾蜍属', 'Bufo', [['中华蟾蜍', 'Bufo gargarizans']]],
            ]],
          ]],
        ]],
        ['硬骨鱼纲', 'Osteichthyes', [
          ['鲤形目', 'Cypriniformes', [
            ['鲤科', 'Cyprinidae', [
              ['鲤属', 'Cyprinus', [['鲤', 'Cyprinus carpio']]],
              ['鲢属', 'Hypophthalmichthys', [['鲢', 'Hypophthalmichthys molitrix'], ['鳙', 'Hypophthalmichthys nobilis']]],
            ]],
          ]],
          ['鲈形目', 'Perciformes', [
            ['狼鲈科', 'Moronidae', [
              ['花鲈属', 'Lateolabrax', [['日本花鲈', 'Lateolabrax japonicus']]],
            ]],
          ]],
        ]],
        ['软骨鱼纲', 'Chondrichthyes', [
          ['真鲨目', 'Carcharhiniformes', [
            ['真鲨科', 'Carcharhinidae', [
              ['真鲨属', 'Carcharhinus', [['沙拉真鲨', 'Carcharhinus sorrah']]],
              ['大青鲨属', 'Prionace', [['大青鲨', 'Prionace glauca']]],
            ]],
          ]],
        ]],
      ]],
      ['节肢动物门', 'Arthropoda', [
        ['昆虫纲', 'Insecta', [
          ['鞘翅目', 'Coleoptera', [
            ['瓢虫科', 'Coccinellidae', [
              ['异色瓢虫属', 'Harmonia', [['异色瓢虫', 'Harmonia axyridis']]],
            ]],
            ['步甲科', 'Carabidae', [
              ['步甲属', 'Carabus', [['绿步甲', 'Carabus smaragdinus']]],
            ]],
          ]],
          ['鳞翅目', 'Lepidoptera', [
            ['凤蝶科', 'Papilionidae', [
              ['凤蝶属', 'Papilio', [['金凤蝶', 'Papilio machaon']]],
            ]],
            ['粉蝶科', 'Pieridae', [
              ['粉蝶属', 'Pieris', [['菜粉蝶', 'Pieris rapae']]],
            ]],
          ]],
          ['膜翅目', 'Hymenoptera', [
            ['蜜蜂科', 'Apidae', [
              ['蜜蜂属', 'Apis', [['西方蜜蜂', 'Apis mellifera'], ['中华蜜蜂', 'Apis cerana']]],
            ]],
            ['蚁科', 'Formicidae', [
              ['弓背蚁属', 'Camponotus', [['日本弓背蚁', 'Camponotus japonicus']]],
            ]],
          ]],
          ['双翅目', 'Diptera', [
            ['蚊科', 'Culicidae', [
              ['按蚊属', 'Anopheles', [['中华按蚊', 'Anopheles sinensis']]],
            ]],
            ['蝇科', 'Muscidae', [
              ['蝇属', 'Musca', [['家蝇', 'Musca domestica']]],
            ]],
          ]],
          ['蜻蜓目', 'Odonata', [
            ['蜻科', 'Libellulidae', [
              ['赤蜻属', 'Sympetrum', [['条斑赤蜻', 'Sympetrum striolatum']]],
            ]],
          ]],
        ]],
        ['蛛形纲', 'Arachnida', [
          ['蜘蛛目', 'Araneae', [
            ['园蛛科', 'Araneidae', [
              ['园蛛属', 'Araneus', [['大腹园蛛', 'Araneus ventricosus']]],
            ]],
            ['跳蛛科', 'Salticidae', [
              ['蝇虎属', 'Plexippus', [['双带蝇虎', 'Plexippus paykulli']]],
            ]],
          ]],
          ['蝎目', 'Scorpiones', [
            ['钳蝎科', 'Buthidae', [
              ['正钳蝎属', 'Mesobuthus', [['东亚钳蝎', 'Mesobuthus martensii']]],
            ]],
          ]],
        ]],
        ['软甲纲', 'Malacostraca', [
          ['十足目', 'Decapoda', [
            ['梭子蟹科', 'Portunidae', [
              ['梭子蟹属', 'Portunus', [['三疣梭子蟹', 'Portunus trituberculatus']]],
            ]],
            ['对虾科', 'Penaeidae', [
              ['对虾属', 'Penaeus', [['凡纳滨对虾', 'Penaeus vannamei']]],
              ['明对虾属', 'Fenneropenaeus', [['中国明对虾', 'Fenneropenaeus chinensis']]],
            ]],
          ]],
        ]],
        ['唇足纲', 'Chilopoda', [
          ['蜈蚣目', 'Scolopendromorpha', [
            ['蜈蚣科', 'Scolopendridae', [
              ['蜈蚣属', 'Scolopendra', [['少棘蜈蚣', 'Scolopendra mutilans']]],
            ]],
          ]],
        ]],
      ]],
      ['软体动物门', 'Mollusca', [
        ['腹足纲', 'Gastropoda', [
          ['柄眼目', 'Stylommatophora', [
            ['巴蜗牛科', 'Bradybaenidae', [
              ['巴蜗牛属', 'Bradybaena', [['同型巴蜗牛', 'Bradybaena similaris']]],
            ]],
          ]],
          ['中腹足目', 'Mesogastropoda', [
            ['田螺科', 'Viviparidae', [
              ['圆田螺属', 'Cipangopaludina', [['中华圆田螺', 'Cipangopaludina cathayensis']]],
            ]],
          ]],
        ]],
        ['双壳纲', 'Bivalvia', [
          ['贻贝目', 'Mytilida', [
            ['贻贝科', 'Mytilidae', [
              ['贻贝属', 'Mytilus', [['紫贻贝', 'Mytilus edulis']]],
            ]],
          ]],
          ['珍珠贝目', 'Pterioida', [
            ['牡蛎科', 'Ostreidae', [
              ['巨牡蛎属', 'Crassostrea', [['长牡蛎', 'Crassostrea gigas']]],
            ]],
          ]],
        ]],
        ['头足纲', 'Cephalopoda', [
          ['八腕目', 'Octopoda', [
            ['章鱼科', 'Octopodidae', [
              ['章鱼属', 'Octopus', [['普通章鱼', 'Octopus vulgaris']]],
            ]],
          ]],
          ['枪形目', 'Teuthida', [
            ['枪乌贼科', 'Loliginidae', [
              ['枪乌贼属', 'Loligo', [['日本枪乌贼', 'Loligo japonica']]],
            ]],
          ]],
        ]],
        ['多板纲', 'Polyplacophora', [
          ['石鳖目', 'Chitonida', [
            ['石鳖科', 'Chitonidae', [
              ['石鳖属', 'Chiton', [['日本石鳖', 'Chiton japonicus']]],
            ]],
          ]],
        ]],
      ]],
      ['环节动物门', 'Annelida', [
        ['寡毛纲', 'Oligochaeta', [
          ['正蚓目', 'Crassiclitellata', [
            ['正蚓科', 'Lumbricidae', [
              ['正蚓属', 'Lumbricus', [['欧洲正蚓', 'Lumbricus terrestris']]],
            ]],
            ['巨蚓科', 'Megascolecidae', [
              ['环毛蚓属', 'Metaphire', [['威廉环毛蚓', 'Metaphire guillelmi']]],
            ]],
          ]],
        ]],
        ['多毛纲', 'Polychaeta', [
          ['叶须虫目', 'Phyllodocida', [
            ['沙蚕科', 'Nereididae', [
              ['沙蚕属', 'Nereis', [['红角沙蚕', 'Nereis pelagica']]],
            ]],
          ]],
        ]],
        ['蛭纲', 'Hirudinea', [
          ['无吻蛭目', 'Arhynchobdellida', [
            ['医蛭科', 'Hirudinidae', [
              ['医蛭属', 'Hirudo', [['日本医蛭', 'Hirudo nipponia']]],
            ]],
          ]],
        ]],
      ]],
      ['线虫动物门', 'Nematoda', [
        ['色矛纲', 'Chromadorea', [
          ['小杆目', 'Rhabditida', [
            ['蛔虫科', 'Ascarididae', [
              ['蛔属', 'Ascaris', [['人蛔虫', 'Ascaris lumbricoides']]],
            ]],
            ['隐杆线虫科', 'Rhabditidae', [
              ['隐杆线虫属', 'Caenorhabditis', [['秀丽隐杆线虫', 'Caenorhabditis elegans']]],
            ]],
          ]],
        ]],
        ['刺嘴纲', 'Enoplea', [
          ['毛形目', 'Trichocephalida', [
            ['鞭虫科', 'Trichuridae', [
              ['鞭虫属', 'Trichuris', [['人鞭虫', 'Trichuris trichiura']]],
            ]],
          ]],
        ]],
      ]],
      ['刺胞动物门', 'Cnidaria', [
        ['水螅纲', 'Hydrozoa', [
          ['水螅目', 'Hydroida', [
            ['水螅科', 'Hydridae', [
              ['水螅属', 'Hydra', [['普通水螅', 'Hydra vulgaris']]],
            ]],
          ]],
        ]],
        ['钵水母纲', 'Scyphozoa', [
          ['海月水母目', 'Semaeostomeae', [
            ['海月水母科', 'Ulmaridae', [
              ['海月水母属', 'Aurelia', [['海月水母', 'Aurelia aurita']]],
            ]],
          ]],
        ]],
        ['珊瑚纲', 'Anthozoa', [
          ['石珊瑚目', 'Scleractinia', [
            ['鹿角珊瑚科', 'Acroporidae', [
              ['鹿角珊瑚属', 'Acropora', [['蓬勃鹿角珊瑚', 'Acropora humilis']]],
            ]],
          ]],
          ['海葵目', 'Actiniaria', [
            ['海葵科', 'Actiniidae', [
              ['海葵属', 'Actinia', [['红海葵', 'Actinia equina']]],
            ]],
          ]],
        ]],
      ]],
      ['棘皮动物门', 'Echinodermata', [
        ['海星纲', 'Asteroidea', [
          ['钳棘目', 'Forcipulatida', [
            ['海星科', 'Asteriidae', [
              ['海盘车属', 'Asterias', [['多棘海盘车', 'Asterias amurensis']]],
            ]],
          ]],
        ]],
        ['海胆纲', 'Echinoidea', [
          ['拱齿目', 'Camarodonta', [
            ['球海胆科', 'Strongylocentrotidae', [
              ['球海胆属', 'Strongylocentrotus', [['中间球海胆', 'Strongylocentrotus intermedius']]],
            ]],
          ]],
        ]],
        ['海参纲', 'Holothuroidea', [
          ['楯手目', 'Aspidochirotida', [
            ['海参科', 'Holothuriidae', [
              ['海参属', 'Holothuria', [['黑海参', 'Holothuria atra']]],
            ]],
          ]],
        ]],
        ['海百合纲', 'Crinoidea', [
          ['羽枝目', 'Comatulida', [
            ['栉羽枝科', 'Comasteridae', [
              ['栉羽枝属', 'Comanthus', [['日本栉羽枝', 'Comanthus japonicus']]],
            ]],
          ]],
        ]],
      ]],
      ['扁形动物门', 'Platyhelminthes', [
        ['涡虫纲', 'Turbellaria', [
          ['三肠目', 'Tricladida', [
            ['三角涡虫科', 'Dugesiidae', [
              ['三角涡虫属', 'Dugesia', [['日本三角涡虫', 'Dugesia japonica']]],
            ]],
          ]],
        ]],
        ['吸虫纲', 'Trematoda', [
          ['棘口目', 'Echinostomida', [
            ['片形科', 'Fasciolidae', [
              ['片形属', 'Fasciola', [['肝片形吸虫', 'Fasciola hepatica']]],
            ]],
          ]],
          ['双穴目', 'Diplostomida', [
            ['血吸虫科', 'Schistosomatidae', [
              ['血吸虫属', 'Schistosoma', [['日本血吸虫', 'Schistosoma japonicum']]],
            ]],
          ]],
        ]],
        ['绦虫纲', 'Cestoda', [
          ['圆叶目', 'Cyclophyllidea', [
            ['带绦虫科', 'Taeniidae', [
              ['带绦虫属', 'Taenia', [['猪带绦虫', 'Taenia solium'], ['牛带绦虫', 'Taenia saginata']]],
            ]],
          ]],
        ]],
      ]],
      ['多孔动物门', 'Porifera', [
        ['寻常海绵纲', 'Demospongiae', [
          ['简骨海绵目', 'Haplosclerida', [
            ['淡水海绵科', 'Spongillidae', [
              ['针海绵属', 'Spongilla', [['湖针海绵', 'Spongilla lacustris']]],
            ]],
          ]],
        ]],
        ['钙质海绵纲', 'Calcarea', [
          ['白枝海绵目', 'Leucosolenida', [
            ['白枝海绵科', 'Leucosoleniidae', [
              ['白枝海绵属', 'Leucosolenia', [['葡萄白枝海绵', 'Leucosolenia botryoides']]],
            ]],
          ]],
        ]],
      ]],
      ['轮形动物门', 'Rotifera', [
        ['单巢纲', 'Monogononta', [
          ['游泳目', 'Ploima', [
            ['臂尾轮科', 'Brachionidae', [
              ['臂尾轮属', 'Brachionus', [['褶皱臂尾轮虫', 'Brachionus plicatilis']]],
            ]],
          ]],
        ]],
        ['双巢纲', 'Digononta', [
          ['蛭态目', 'Bdelloidea', [
            ['旋轮科', 'Philodinidae', [
              ['旋轮属', 'Philodina', [['玫瑰旋轮虫', 'Philodina roseola']]],
            ]],
          ]],
        ]],
      ]],
      ['缓步动物门', 'Tardigrada', [
        ['真缓步纲', 'Eutardigrada', [
          ['近爪目', 'Parachela', [
            ['大生科', 'Macrobiotidae', [
              ['大生属', 'Macrobiotus', [['胡氏大生', 'Macrobiotus hufelandi']]],
            ]],
          ]],
        ]],
        ['异缓步纲', 'Heterotardigrada', [
          ['棘节目', 'Echiniscoidea', [
            ['棘影科', 'Echiniscidae', [
              ['棘影属', 'Echiniscus', [['红棘影', 'Echiniscus testudo']]],
            ]],
          ]],
        ]],
      ]],
      ['纽形动物门', 'Nemertea', [
        ['无针纲', 'Anopla', [
          ['异纽目', 'Heteronemertea', [
            ['线纽科', 'Lineidae', [
              ['线纽属', 'Lineus', [['绿线纽虫', 'Lineus viridis']]],
            ]],
          ]],
        ]],
        ['有针纲', 'Enopla', [
          ['针纽目', 'Hoplonemertea', [
            ['两孔纽科', 'Amphiporidae', [
              ['两孔纽属', 'Amphiporus', [['乳突两孔纽虫', 'Amphiporus lactifloreus']]],
            ]],
          ]],
        ]],
      ]],
      ['苔藓动物门', 'Bryozoa', [
        ['被唇纲', 'Phylactolaemata', [
          ['羽苔目', 'Plumatellida', [
            ['羽苔科', 'Plumatellidae', [
              ['羽苔属', 'Plumatella', [['褐色羽苔虫', 'Plumatella repens']]],
            ]],
          ]],
        ]],
        ['裸唇纲', 'Gymnolaemata', [
          ['唇口目', 'Cheilostomatida', [
            ['膜孔苔科', 'Membraniporidae', [
              ['膜孔苔属', 'Membranipora', [['膜孔苔虫', 'Membranipora membranacea']]],
            ]],
          ]],
        ]],
      ]],
    ]],

    /* ============ 植物界 · 10 个门 ============ */
    ['植物界', 'Plantae', [
      ['被子植物门', 'Magnoliophyta', [
        ['双子叶植物纲', 'Magnoliopsida', [
          ['蔷薇目', 'Rosales', [
            ['蔷薇科', 'Rosaceae', [
              ['李属', 'Prunus', [['桃', 'Prunus persica'], ['梅', 'Prunus mume'], ['樱花', 'Prunus serrulata']]],
              ['苹果属', 'Malus', [['苹果', 'Malus pumila']]],
            ]],
          ]],
          ['十字花目', 'Brassicales', [
            ['十字花科', 'Brassicaceae', [
              ['芸苔属', 'Brassica', [['甘蓝', 'Brassica oleracea'], ['白菜', 'Brassica rapa']]],
              ['萝卜属', 'Raphanus', [['萝卜', 'Raphanus sativus']]],
            ]],
          ]],
          ['唇形目', 'Lamiales', [
            ['唇形科', 'Lamiaceae', [
              ['薄荷属', 'Mentha', [['薄荷', 'Mentha canadensis']]],
              ['鼠尾草属', 'Salvia', [['丹参', 'Salvia miltiorrhiza']]],
            ]],
          ]],
          ['杜鹃花目', 'Ericales', [
            ['山茶科', 'Theaceae', [
              ['山茶属', 'Camellia', [['茶', 'Camellia sinensis'], ['山茶', 'Camellia japonica']]],
            ]],
          ]],
        ]],
        ['单子叶植物纲', 'Liliopsida', [
          ['禾本目', 'Poales', [
            ['禾本科', 'Poaceae', [
              ['稻属', 'Oryza', [['水稻', 'Oryza sativa']]],
              ['小麦属', 'Triticum', [['普通小麦', 'Triticum aestivum']]],
              ['玉蜀黍属', 'Zea', [['玉米', 'Zea mays']]],
            ]],
          ]],
          ['天门冬目', 'Asparagales', [
            ['兰科', 'Orchidaceae', [
              ['兰属', 'Cymbidium', [['建兰', 'Cymbidium ensifolium']]],
              ['石斛属', 'Dendrobium', [['铁皮石斛', 'Dendrobium officinale']]],
            ]],
          ]],
          ['百合目', 'Liliales', [
            ['百合科', 'Liliaceae', [
              ['百合属', 'Lilium', [['卷丹', 'Lilium lancifolium']]],
            ]],
          ]],
        ]],
      ]],
      ['裸子植物门', 'Pinophyta', [
        ['松纲', 'Pinopsida', [
          ['松目', 'Pinales', [
            ['松科', 'Pinaceae', [
              ['松属', 'Pinus', [['马尾松', 'Pinus massoniana'], ['油松', 'Pinus tabuliformis']]],
              ['冷杉属', 'Abies', [['杉松', 'Abies holophylla']]],
            ]],
            ['柏科', 'Cupressaceae', [
              ['侧柏属', 'Platycladus', [['侧柏', 'Platycladus orientalis']]],
            ]],
          ]],
        ]],
        ['银杏纲', 'Ginkgoopsida', [
          ['银杏目', 'Ginkgoales', [
            ['银杏科', 'Ginkgoaceae', [
              ['银杏属', 'Ginkgo', [['银杏', 'Ginkgo biloba']]],
            ]],
          ]],
        ]],
        ['苏铁纲', 'Cycadopsida', [
          ['苏铁目', 'Cycadales', [
            ['苏铁科', 'Cycadaceae', [
              ['苏铁属', 'Cycas', [['苏铁', 'Cycas revoluta']]],
            ]],
          ]],
        ]],
      ]],
      ['蕨类植物门', 'Pteridophyta', [
        ['真蕨纲', 'Polypodiopsida', [
          ['水龙骨目', 'Polypodiales', [
            ['鳞毛蕨科', 'Dryopteridaceae', [
              ['鳞毛蕨属', 'Dryopteris', [['阔鳞鳞毛蕨', 'Dryopteris championii']]],
            ]],
            ['凤尾蕨科', 'Pteridaceae', [
              ['凤尾蕨属', 'Pteris', [['井栏凤尾蕨', 'Pteris multifida']]],
            ]],
          ]],
        ]],
        ['木贼纲', 'Equisetopsida', [
          ['木贼目', 'Equisetales', [
            ['木贼科', 'Equisetaceae', [
              ['木贼属', 'Equisetum', [['问荆', 'Equisetum arvense']]],
            ]],
          ]],
        ]],
      ]],
      ['石松门', 'Lycopodiophyta', [
        ['石松纲', 'Lycopodiopsida', [
          ['石松目', 'Lycopodiales', [
            ['石松科', 'Lycopodiaceae', [
              ['石松属', 'Lycopodium', [['石松', 'Lycopodium clavatum']]],
            ]],
          ]],
        ]],
        ['卷柏纲', 'Selaginellopsida', [
          ['卷柏目', 'Selaginellales', [
            ['卷柏科', 'Selaginellaceae', [
              ['卷柏属', 'Selaginella', [['卷柏', 'Selaginella tamariscina'], ['翠云草', 'Selaginella uncinata']]],
            ]],
          ]],
        ]],
      ]],
      ['苔藓植物门', 'Bryophyta', [
        ['真藓纲', 'Bryopsida', [
          ['真藓目', 'Bryales', [
            ['真藓科', 'Bryaceae', [
              ['真藓属', 'Bryum', [['银叶真藓', 'Bryum argenteum']]],
            ]],
          ]],
          ['灰藓目', 'Hypnales', [
            ['羽藓科', 'Thuidiaceae', [
              ['羽藓属', 'Thuidium', [['大羽藓', 'Thuidium cymbifolium']]],
            ]],
          ]],
        ]],
        ['泥炭藓纲', 'Sphagnopsida', [
          ['泥炭藓目', 'Sphagnales', [
            ['泥炭藓科', 'Sphagnaceae', [
              ['泥炭藓属', 'Sphagnum', [['泥炭藓', 'Sphagnum palustre']]],
            ]],
          ]],
        ]],
      ]],
      ['地钱门', 'Marchantiophyta', [
        ['地钱纲', 'Marchantiopsida', [
          ['地钱目', 'Marchantiales', [
            ['地钱科', 'Marchantiaceae', [
              ['地钱属', 'Marchantia', [['地钱', 'Marchantia polymorpha']]],
            ]],
          ]],
        ]],
        ['叶苔纲', 'Jungermanniopsida', [
          ['叶苔目', 'Jungermanniales', [
            ['叶苔科', 'Jungermanniaceae', [
              ['叶苔属', 'Jungermannia', [['叶苔', 'Jungermannia lanceolata']]],
            ]],
          ]],
        ]],
      ]],
      ['绿藻门', 'Chlorophyta', [
        ['绿藻纲', 'Chlorophyceae', [
          ['衣藻目', 'Chlamydomonadales', [
            ['衣藻科', 'Chlamydomonadaceae', [
              ['衣藻属', 'Chlamydomonas', [['莱茵衣藻', 'Chlamydomonas reinhardtii']]],
            ]],
          ]],
        ]],
        ['石莼纲', 'Ulvophyceae', [
          ['石莼目', 'Ulvales', [
            ['石莼科', 'Ulvaceae', [
              ['石莼属', 'Ulva', [['石莼', 'Ulva lactuca']]],
              ['浒苔属', 'Enteromorpha', [['浒苔', 'Enteromorpha prolifera']]],
            ]],
          ]],
        ]],
      ]],
      ['轮藻门', 'Charophyta', [
        ['轮藻纲', 'Charophyceae', [
          ['轮藻目', 'Charales', [
            ['轮藻科', 'Characeae', [
              ['轮藻属', 'Chara', [['普生轮藻', 'Chara vulgaris']]],
            ]],
          ]],
        ]],
        ['接合藻纲', 'Zygnematophyceae', [
          ['双星藻目', 'Zygnematales', [
            ['水绵科', 'Zygnemataceae', [
              ['水绵属', 'Spirogyra', [['水绵', 'Spirogyra communis']]],
            ]],
          ]],
        ]],
      ]],
      ['红藻门', 'Rhodophyta', [
        ['真红藻纲', 'Florideophyceae', [
          ['石花菜目', 'Gelidiales', [
            ['石花菜科', 'Gelidiaceae', [
              ['石花菜属', 'Gelidium', [['石花菜', 'Gelidium amansii']]],
            ]],
          ]],
          ['仙菜目', 'Ceramiales', [
            ['江蓠科', 'Gracilariaceae', [
              ['江蓠属', 'Gracilaria', [['江蓠', 'Gracilaria vermiculophylla']]],
            ]],
          ]],
        ]],
        ['红藻纲', 'Rhodophyceae', [
          ['紫菜目', 'Bangiales', [
            ['红毛菜科', 'Bangiaceae', [
              ['紫菜属', 'Pyropia', [['条斑紫菜', 'Pyropia yezoensis']]],
            ]],
          ]],
        ]],
      ]],
      ['褐藻门', 'Ochrophyta', [
        ['褐藻纲', 'Phaeophyceae', [
          ['海带目', 'Laminariales', [
            ['海带科', 'Laminariaceae', [
              ['糖海带属', 'Saccharina', [['海带', 'Saccharina japonica']]],
            ]],
          ]],
          ['墨角藻目', 'Fucales', [
            ['马尾藻科', 'Sargassaceae', [
              ['马尾藻属', 'Sargassum', [['铜藻', 'Sargassum horneri']]],
            ]],
          ]],
        ]],
        ['硅鞭藻纲', 'Dictyochophyceae', [
          ['硅鞭藻目', 'Dictyochales', [
            ['硅鞭藻科', 'Dictyochaceae', [
              ['硅鞭藻属', 'Dictyocha', [['小硅鞭藻', 'Dictyocha fibula']]],
            ]],
          ]],
        ]],
      ]],
    ]],

    /* ============ 真菌界 · 5 个门 ============ */
    ['真菌界', 'Fungi', [
      ['子囊菌门', 'Ascomycota', [
        ['酵母纲', 'Saccharomycetes', [
          ['酵母目', 'Saccharomycetales', [
            ['酵母科', 'Saccharomycetaceae', [
              ['酵母属', 'Saccharomyces', [['酿酒酵母', 'Saccharomyces cerevisiae']]],
            ]],
          ]],
        ]],
        ['散囊菌纲', 'Eurotiomycetes', [
          ['散囊菌目', 'Eurotiales', [
            ['曲霉科', 'Aspergillaceae', [
              ['曲霉属', 'Aspergillus', [['黑曲霉', 'Aspergillus niger'], ['米曲霉', 'Aspergillus oryzae']]],
              ['青霉属', 'Penicillium', [['产黄青霉', 'Penicillium chrysogenum']]],
            ]],
          ]],
        ]],
        ['粪壳菌纲', 'Sordariomycetes', [
          ['肉座菌目', 'Hypocreales', [
            ['虫草科', 'Cordycipitaceae', [
              ['虫草属', 'Cordyceps', [['蛹虫草', 'Cordyceps militaris']]],
            ]],
          ]],
        ]],
      ]],
      ['担子菌门', 'Basidiomycota', [
        ['伞菌纲', 'Agaricomycetes', [
          ['伞菌目', 'Agaricales', [
            ['蘑菇科', 'Agaricaceae', [
              ['蘑菇属', 'Agaricus', [['双孢蘑菇', 'Agaricus bisporus']]],
            ]],
            ['侧耳科', 'Pleurotaceae', [
              ['侧耳属', 'Pleurotus', [['糙皮侧耳', 'Pleurotus ostreatus']]],
            ]],
            ['红菇科', 'Russulaceae', [
              ['红菇属', 'Russula', [['大红菇', 'Russula alutacea']]],
            ]],
          ]],
        ]],
        ['银耳纲', 'Tremellomycetes', [
          ['银耳目', 'Tremellales', [
            ['银耳科', 'Tremellaceae', [
              ['银耳属', 'Tremella', [['银耳', 'Tremella fuciformis']]],
            ]],
          ]],
        ]],
      ]],
      ['毛霉门', 'Mucoromycota', [
        ['毛霉纲', 'Mucoromycetes', [
          ['毛霉目', 'Mucorales', [
            ['毛霉科', 'Mucoraceae', [
              ['根霉属', 'Rhizopus', [['匍枝根霉', 'Rhizopus stolonifer']]],
              ['毛霉属', 'Mucor', [['总状毛霉', 'Mucor racemosus']]],
            ]],
          ]],
        ]],
        ['被孢霉纲', 'Mortierellomycetes', [
          ['被孢霉目', 'Mortierellales', [
            ['被孢霉科', 'Mortierellaceae', [
              ['被孢霉属', 'Mortierella', [['高山被孢霉', 'Mortierella alpina']]],
            ]],
          ]],
        ]],
      ]],
      ['壶菌门', 'Chytridiomycota', [
        ['壶菌纲', 'Chytridiomycetes', [
          ['壶菌目', 'Chytridiales', [
            ['壶菌科', 'Chytridiaceae', [
              ['壶菌属', 'Chytridium', [['球壶菌', 'Chytridium olla']]],
            ]],
          ]],
        ]],
        ['蛙壶菌纲', 'Batrachochytriomycetes', [
          ['根壶菌目', 'Rhizophydiales', [
            ['蛙壶菌科', 'Batrachochytriaceae', [
              ['蛙壶菌属', 'Batrachochytrium', [['蛙壶菌', 'Batrachochytrium dendrobatidis']]],
            ]],
          ]],
        ]],
      ]],
      ['球囊菌门', 'Glomeromycota', [
        ['球囊菌纲', 'Glomeromycetes', [
          ['球囊菌目', 'Glomerales', [
            ['球囊菌科', 'Glomeraceae', [
              ['根内球囊霉属', 'Rhizophagus', [['根内球囊霉', 'Rhizophagus intraradices']]],
            ]],
          ]],
        ]],
        ['巨孢囊霉纲', 'Gigasporomycetes', [
          ['巨孢囊霉目', 'Gigasporales', [
            ['巨孢囊霉科', 'Gigasporaceae', [
              ['巨孢囊霉属', 'Gigaspora', [['珍珠巨孢囊霉', 'Gigaspora margarita']]],
            ]],
          ]],
        ]],
      ]],
    ]],

    /* ============ 原生生物界 · 6 个门 ============ */
    ['原生生物界', 'Protista', [
      ['纤毛门', 'Ciliophora', [
        ['草履虫纲', 'Oligohymenophorea', [
          ['膜口目', 'Hymenostomatida', [
            ['草履虫科', 'Parameciidae', [
              ['草履虫属', 'Paramecium', [['大草履虫', 'Paramecium caudatum'], ['尾草履虫', 'Paramecium caudatum']]],
            ]],
            ['四膜虫科', 'Tetrahymenidae', [
              ['四膜虫属', 'Tetrahymena', [['梨形四膜虫', 'Tetrahymena pyriformis']]],
            ]],
          ]],
        ]],
        ['旋毛纲', 'Spirotrichea', [
          ['游仆目', 'Euplotida', [
            ['游仆科', 'Euplotidae', [
              ['游仆属', 'Euplotes', [['盘状游仆虫', 'Euplotes patella']]],
            ]],
          ]],
        ]],
      ]],
      ['变形虫门', 'Amoebozoa', [
        ['管状变形虫纲', 'Tubulinea', [
          ['变形目', 'Amoebida', [
            ['变形虫科', 'Amoebidae', [
              ['变形虫属', 'Amoeba', [['大变形虫', 'Amoeba proteus']]],
            ]],
          ]],
        ]],
        ['网柄菌纲', 'Dictyosteliomycetes', [
          ['网柄菌目', 'Dictyosteliales', [
            ['网柄菌科', 'Dictyosteliaceae', [
              ['网柄菌属', 'Dictyostelium', [['盘基网柄菌', 'Dictyostelium discoideum']]],
            ]],
          ]],
        ]],
      ]],
      ['眼虫门', 'Euglenozoa', [
        ['眼虫纲', 'Euglenoidea', [
          ['眼虫目', 'Euglenales', [
            ['眼虫科', 'Euglenaceae', [
              ['眼虫属', 'Euglena', [['绿眼虫', 'Euglena viridis'], ['细长眼虫', 'Euglena gracilis']]],
            ]],
          ]],
        ]],
        ['动质体纲', 'Kinetoplastea', [
          ['锥虫目', 'Trypanosomatida', [
            ['锥虫科', 'Trypanosomatidae', [
              ['锥虫属', 'Trypanosoma', [['布氏锥虫', 'Trypanosoma brucei']]],
              ['利什曼属', 'Leishmania', [['杜氏利什曼虫', 'Leishmania donovani']]],
            ]],
          ]],
        ]],
      ]],
      ['顶复门', 'Apicomplexa', [
        ['球虫纲', 'Conoidasida', [
          ['真球虫目', 'Eucoccidiorida', [
            ['疟原虫科', 'Plasmodiidae', [
              ['疟原虫属', 'Plasmodium', [['恶性疟原虫', 'Plasmodium falciparum'], ['间日疟原虫', 'Plasmodium vivax']]],
            ]],
            ['肉孢子虫科', 'Sarcocystidae', [
              ['弓形虫属', 'Toxoplasma', [['刚地弓形虫', 'Toxoplasma gondii']]],
            ]],
          ]],
        ]],
        ['簇虫纲', 'Gregarinomorpha', [
          ['簇虫目', 'Eugregarinorida', [
            ['簇虫科', 'Gregarinidae', [
              ['簇虫属', 'Gregarina', [['蚤缀簇虫', 'Gregarina polymorpha']]],
            ]],
          ]],
        ]],
      ]],
      ['硅藻门', 'Bacillariophyta', [
        ['圆筛藻纲', 'Coscinodiscophyceae', [
          ['圆筛藻目', 'Coscinodiscales', [
            ['圆筛藻科', 'Coscinodiscaceae', [
              ['圆筛藻属', 'Coscinodiscus', [['星脐圆筛藻', 'Coscinodiscus asteromphalus']]],
            ]],
          ]],
        ]],
        ['硅藻纲', 'Bacillariophyceae', [
          ['舟形藻目', 'Naviculales', [
            ['舟形藻科', 'Naviculaceae', [
              ['舟形藻属', 'Navicula', [['放射舟形藻', 'Navicula radiosa']]],
            ]],
          ]],
        ]],
      ]],
      ['有孔虫门', 'Foraminifera', [
        ['球有孔虫纲', 'Globothalamea', [
          ['轮虫目', 'Rotaliida', [
            ['轮虫科', 'Rotaliidae', [
              ['轮虫属', 'Rotalia', [['轮有孔虫', 'Rotalia beccarii']]],
            ]],
          ]],
        ]],
        ['丝状有孔虫纲', 'Tubothalamea', [
          ['小粟虫目', 'Miliolida', [
            ['小粟虫科', 'Miliolidae', [
              ['小粟虫属', 'Miliola', [['小粟虫', 'Miliola semiulum']]],
            ]],
          ]],
        ]],
      ]],
    ]],

    /* ============ 细菌界 · 7 个门 ============ */
    ['细菌界', 'Bacteria', [
      ['变形菌门', 'Proteobacteria', [
        ['γ-变形菌纲', 'Gammaproteobacteria', [
          ['肠杆菌目', 'Enterobacterales', [
            ['肠杆菌科', 'Enterobacteriaceae', [
              ['埃希菌属', 'Escherichia', [['大肠杆菌', 'Escherichia coli']]],
              ['沙门菌属', 'Salmonella', [['肠道沙门菌', 'Salmonella enterica']]],
            ]],
          ]],
        ]],
        ['α-变形菌纲', 'Alphaproteobacteria', [
          ['根瘤菌目', 'Rhizobiales', [
            ['根瘤菌科', 'Rhizobiaceae', [
              ['根瘤菌属', 'Rhizobium', [['豌豆根瘤菌', 'Rhizobium leguminosarum']]],
            ]],
          ]],
        ]],
      ]],
      ['厚壁菌门', 'Firmicutes', [
        ['芽孢杆菌纲', 'Bacilli', [
          ['芽孢杆菌目', 'Bacillales', [
            ['芽孢杆菌科', 'Bacillaceae', [
              ['芽孢杆菌属', 'Bacillus', [['枯草芽孢杆菌', 'Bacillus subtilis']]],
            ]],
          ]],
          ['乳杆菌目', 'Lactobacillales', [
            ['乳杆菌科', 'Lactobacillaceae', [
              ['乳杆菌属', 'Lactobacillus', [['嗜酸乳杆菌', 'Lactobacillus acidophilus']]],
            ]],
          ]],
        ]],
        ['梭菌纲', 'Clostridia', [
          ['梭菌目', 'Clostridiales', [
            ['梭菌科', 'Clostridiaceae', [
              ['梭菌属', 'Clostridium', [['丙酮丁醇梭菌', 'Clostridium acetobutylicum']]],
            ]],
          ]],
        ]],
      ]],
      ['放线菌门', 'Actinobacteria', [
        ['放线菌纲', 'Actinobacteria', [
          ['放线菌目', 'Actinomycetales', [
            ['链霉菌科', 'Streptomycetaceae', [
              ['链霉菌属', 'Streptomyces', [['灰色链霉菌', 'Streptomyces griseus']]],
            ]],
          ]],
          ['分枝杆菌目', 'Mycobacteriales', [
            ['分枝杆菌科', 'Mycobacteriaceae', [
              ['分枝杆菌属', 'Mycobacterium', [['结核分枝杆菌', 'Mycobacterium tuberculosis']]],
            ]],
          ]],
        ]],
        ['红蝽菌纲', 'Coriobacteriia', [
          ['红蝽菌目', 'Coriobacteriales', [
            ['红蝽菌科', 'Coriobacteriaceae', [
              ['红蝽菌属', 'Coriobacterium', [['肾形红蝽菌', 'Coriobacterium glomerans']]],
            ]],
          ]],
        ]],
      ]],
      ['蓝细菌门', 'Cyanobacteria', [
        ['颤藻纲', 'Oscillatoriophycideae', [
          ['颤藻目', 'Oscillatoriales', [
            ['颤藻科', 'Oscillatoriaceae', [
              ['颤藻属', 'Oscillatoria', [['弱细颤藻', 'Oscillatoria tenuis']]],
            ]],
          ]],
        ]],
        ['念珠藻纲', 'Nostocophyceae', [
          ['念珠藻目', 'Nostocales', [
            ['念珠藻科', 'Nostocaceae', [
              ['念珠藻属', 'Nostoc', [['普通念珠藻', 'Nostoc commune']]],
              ['鱼腥藻属', 'Anabaena', [['水华鱼腥藻', 'Anabaena flos-aquae']]],
            ]],
          ]],
        ]],
      ]],
      ['拟杆菌门', 'Bacteroidetes', [
        ['拟杆菌纲', 'Bacteroidia', [
          ['拟杆菌目', 'Bacteroidales', [
            ['拟杆菌科', 'Bacteroidaceae', [
              ['拟杆菌属', 'Bacteroides', [['脆弱拟杆菌', 'Bacteroides fragilis']]],
            ]],
          ]],
        ]],
        ['黄杆菌纲', 'Flavobacteriia', [
          ['黄杆菌目', 'Flavobacteriales', [
            ['黄杆菌科', 'Flavobacteriaceae', [
              ['黄杆菌属', 'Flavobacterium', [['水黄杆菌', 'Flavobacterium aquatile']]],
            ]],
          ]],
        ]],
      ]],
      ['螺旋体门', 'Spirochaetes', [
        ['螺旋体纲', 'Spirochaetia', [
          ['螺旋体目', 'Spirochaetales', [
            ['螺旋体科', 'Spirochaetaceae', [
              ['密螺旋体属', 'Treponema', [['苍白密螺旋体', 'Treponema pallidum']]],
              ['疏螺旋体属', 'Borrelia', [['伯氏疏螺旋体', 'Borrelia burgdorferi']]],
            ]],
          ]],
        ]],
        ['短螺旋体纲', 'Brachyspiria', [
          ['短螺旋体目', 'Brachyspirales', [
            ['短螺旋体科', 'Brachyspiraceae', [
              ['短螺旋体属', 'Brachyspira', [['猪痢短螺旋体', 'Brachyspira hyodysenteriae']]],
            ]],
          ]],
        ]],
      ]],
      ['衣原体门', 'Chlamydiae', [
        ['衣原体纲', 'Chlamydiia', [
          ['衣原体目', 'Chlamydiales', [
            ['衣原体科', 'Chlamydiaceae', [
              ['衣原体属', 'Chlamydia', [['沙眼衣原体', 'Chlamydia trachomatis']]],
            ]],
          ]],
        ]],
        ['副衣原体纲', 'Parachlamydiia', [
          ['副衣原体目', 'Parachlamydiales', [
            ['副衣原体科', 'Parachlamydiaceae', [
              ['副衣原体属', 'Parachlamydia', [['棘阿米巴副衣原体', 'Parachlamydia acanthamoebae']]],
            ]],
          ]],
        ]],
      ]],
    ]],

    /* ============ 古菌界 · 2 个门 ============ */
    ['古菌界', 'Archaea', [
      ['广古菌门', 'Euryarchaeota', [
        ['甲烷杆菌纲', 'Methanobacteria', [
          ['甲烷杆菌目', 'Methanobacteriales', [
            ['甲烷杆菌科', 'Methanobacteriaceae', [
              ['甲烷杆菌属', 'Methanobacterium', [['巴氏甲烷杆菌', 'Methanobacterium palustre']]],
            ]],
          ]],
        ]],
        ['盐杆菌纲', 'Halobacteria', [
          ['盐杆菌目', 'Halobacteriales', [
            ['盐杆菌科', 'Halobacteriaceae', [
              ['盐杆菌属', 'Halobacterium', [['盐沼盐杆菌', 'Halobacterium salinarum']]],
            ]],
          ]],
        ]],
      ]],
      ['泉古菌门', 'Crenarchaeota', [
        ['热变形菌纲', 'Thermoprotei', [
          ['硫叶菌目', 'Sulfolobales', [
            ['硫叶菌科', 'Sulfolobaceae', [
              ['硫叶菌属', 'Sulfolobus', [['酸热硫叶菌', 'Sulfolobus acidocaldarius']]],
            ]],
          ]],
        ]],
        ['热丝菌纲', 'Thermofiliomycetes', [
          ['热丝菌目', 'Thermofilales', [
            ['热丝菌科', 'Thermofilaceae', [
              ['热丝菌属', 'Thermofilum', [['下垂热丝菌', 'Thermofilum pendens']]],
            ]],
          ]],
        ]],
      ]],
    ]],
  ],
};
