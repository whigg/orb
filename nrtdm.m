classdef nrtdm
  %static
  properties(Constant)
    %default value of some internal parameters
    default_list=struct(...
      'nrtdm_dir',getenv('NRTDM'),...
      'data_dir',  fullfile(getenv('NRTDM'),'data'),...
      'config_dir',fullfile(getenv('NRTDM'),'config'),...
      'time_format','yyyy-MM-dd hh:mm:ss.sss',...
      'test_time_start',datetime(2015,6,1,12,0,0),...
      'test_time_stop', datetime(2015,6,3,18,0,0),...
      'debug',true...
    );
  end
  %read only
  properties(SetAccess=private)
    metadata
    start
    stop
    ts
    file_list
  end
  %private (visible only to this object)
  properties(GetAccess=private)
  end
  %calculated only when asked fo
  properties(Dependent)
    day_list
  end

  methods(Static)
    function out=data_file_name(data_dir,product,t_now,extension)
      if isempty(dir(data_dir))
        mkdir(data_dir)
      end
      out=fullfile(data_dir,product,...
        [datestr(t_now,'yyyy'), '_',num2str(day(t_now,'dayofyear'),'%03i'),'.',extension]);
    end
    function data_dir=data_dir_fix(hostname)
      if ~exist('hostname','var') || isempty(hostname)
        [~,hostname]=system('hostname');
        hostname=hostname(1:end-1);
      end
      switch lower(hostname)
        case 'tud276672'
          data_dir='/home/teixeira/data/swarm/nrtdmdata/';
        case 'tud14231'
          data_dir='/Users/teixeira/cloud/TUDelft/data/swarm/nrtdmdata/';
        otherwise
          data_dir=nrtdm.default_list.data_dir;
      end
    end
    function test(product_name,time_start,time_stop)
      if ~exist('product_name','var') || isempty(product_name)
        product_name='SC_Panels/Accel_AeroRadiationPressure';
      end
      if ~exist('time_start','var') || isempty(time_start)
        time_start=nrtdm.default_list.test_time_start;
      end
      if ~exist('time_stop','var') || isempty(time_stop)
        time_stop=nrtdm.default_list.test_time_stop;
      end
      data_dir=nrtdm.data_dir_fix;
      if isempty(dir(nrtdm.data_dir_fix))
        disp([mfilename,':WARNING: cannot find NRTDM data dir: ',data_dir,'. Skipping test.'])
        return
      end
      nrtdm(product_name,time_start,time_stop,'data_dir',data_dir).ts.plot
    end
  end
  methods
    function obj=nrtdm(product_name,time_start,time_stop,varargin)
      %inits
      obj.metadata=nrtdm_metadata(product_name);
      obj.start=simpletimeseries.ToDateTime(time_start);
      if ~exist('time_stop','var') || isempty(time_stop)
        obj.stop=obj.start+days(1)-seconds(1);
      else
        obj.stop=simpletimeseries.ToDateTime(time_stop);
      end
      %load data
      obj=obj.load(varargin{:});
    end
    function out=get.day_list(obj)
      [y,m,d] = ymd(obj.start:obj.stop);
      out=datetime(y,m,d);
    end
    function obj=load(obj,varargin)
      %make room for daily data
      daily=cell(size(obj.day_list));
      i=0;
      for t=obj.day_list
        %convert data (faster loading afterwards, skips if already available)
        file=nrtdm_convert(obj.metadata,t,varargin{:});
        i=i+1;
        %only save if file exists
        if isempty(dir(file))
          daily{i}='';
        else
          %save converted matlab data file
          obj=obj.add_file(file);
          %load data
          daily{i}=load(file);
        end
      end
      %concatenate the data
      init_flag=true;
      for i=1:numel(daily)
        if ~isempty(daily{i})
          if init_flag
            obj.ts=daily{i}.ts;
            init_flag=false;
          else
            obj.ts=obj.ts.append(daily{i}.ts);
          end
        end
      end
      %sanity
      if init_flag
        error([mfilename,':nrtdm'],['could not find any valid data for ',obj.metadata.product.str,...
          ' from ',datestr(obj.start),' to ',datestr(obj.stop),'.'])
      end
      %trim to selected start/stop times and fill in time domain
      obj.ts=obj.ts.trim(obj.start,obj.stop).fill;
    end
    function obj=add_file(obj,file)
      if isempty(obj.file_list)
        obj.file_list={file};
      else
        obj.file_list{end+1}=file;
      end
    end
  end

end

%this routine converts NRTDM binary files to Matlab binary files (done on daily terms)
function outfile=nrtdm_convert(metadata,t,varargin)

  %convert input product to metadata
  if isa(metadata,'nrtdm_metadata')
    %do nothing
  elseif isa(metadata,'nrtdm_product')
    metadata=nrtdm_metadata(metadata.str);
  elseif ischar(metadata)
    metadata=nrtdm_metadata(metadata);
  else
    error([mfilename,':nrtdm_convert'],['can not understand class of input ''product'': ''',class(metadata),'''.'])
  end

  % Parse inputs
  p=inputParser;
  p.KeepUnmatched=true;
  % optional arguments
  p.addParameter('nrtdm_args','',@(i)ischar(i));
  p.addParameter('data_dir',  nrtdm.data_dir_fix,  @(i)ischar(i));
  p.addParameter('config_dir',nrtdm.default_list.config_dir,@(i)ischar(i));
  p.addParameter('debug',false,@(i)islogical(i));
  % parse it
  p.parse(varargin{:});

  if isempty(p.Results.nrtdm_args)
    %get NRTDM arguments
    nrtdm_args=[...
      '-noStopIfDataFileMissing ',...
      '-noStopIfAllDataInvalid ',...
      ['-dir_nrtdmconfig="',p.Results.config_dir,'" '],...
      ['-dir_data="',p.Results.data_dir,'"']...
    ];
  end

  %easier names
  t_start=t;
  t_stop =t+days(1)-seconds(1);

  %set specific time system of some satellites
  switch metadata.product.sat
  case {'GA','GB'}
    timesystem='gps';
  otherwise
    timesystem='utc';
  end
  
  %build one-day-long NRTDM time arguments
  timearg=['t=',timesystem,':',...
    datestr(t_start,'yyyymmddHHMMSS'),',',...
    datestr(t_stop, 'yyyymmddHHMMSS')];

  if (p.Results.debug); disp([' ~  Converting data for day ',datestr(t),' : ',metadata.product.str]); end
  infile= metadata.data_filename(t,'orbit',fullfile(p.Results.data_dir,'orbit'));
  outfile=metadata.data_filename(t,'mat',  fullfile(p.Results.data_dir,'mat'));
  if isempty(dir(infile))
    disp(['!!! Cannot find source file : ',infile])
  else
    if file_is_newer(infile,outfile)
      if (p.Results.debug); disp([' ~ Converting data from file: ',infile]); end
      %load nrtdm data
      [time,values]=nrtdm_read(metadata.full_entries,timearg,nrtdm_args);
      %some data files only contain gaps
      if numel(time)<2 || size(values,1)<2
        disp(['!!! Source file filled with gaps, ignoring : ',infile])
        return
      end
      %build data structure
      ts=simpletimeseries(time,values,...
        'y_units',metadata.units,...
        'labels',metadata.fields_no_units,...
        'descriptor',metadata.product.str...
      ).fill;
      %fill extremeties if they are not there (happens a lot in Swarm data)
      if ts.t(1)>t_start
        ts=ts.extend(floor((t_start-ts.t(1))/ts.step));
      end
      if ts.t(end)<t_stop
        ts=ts.extend(floor((t_stop-ts.t(end))/ts.step));
      end
      %fill gaps
      ts=ts.fill; %#ok<NASGU>
      %save it
      save(outfile,'ts');
    else
      if(p.Results.debug); disp([' z  Data already converted  : ',outfile]); end
    end
  end

end

% This is the low-level reading program
function [time,values]=nrtdm_read(product,timearg,nrtdm_args,exportdata)

  debug_now=false;

  if ~exist('exportdata','var') || isempty(exportdata)
    %get NRTDM dir
    nrtdm_dir=getenv('NRTDM');
    if isempty(nrtdm_dir); error([mfilename,':nrtdm_read'],'Could not get NRTDM dir, environmental variable $NRTDM is not defined.'); end
    %build export data utility path and name
    exportdata=fullfile(nrtdm_dir,'bin','exportdataproductscdf.exe');
  end

  if ~exist('nrtdm_args','var')
    nrtdm_args='';
  end

  %setup env
  if ismac
    setenv('DYLD_LIBRARY_PATH',['/usr/local/bin:/opt/local/lib:',getenv('NRTDM'),'/ext/cdf/lib'])
  end

  %get data
  com=[exportdata,' ',product,' ',timearg,' ',nrtdm_args,' -noheader -nofooter -out-screen < /dev/null'];
  if debug_now;disp(['com = ',com]);end

  [status,data_str]=system(com);
  if status ~=0
    error([mfilename,':nrtdm_read'],...
      ['Failed to read data from NRTDM using the following command:',10,...
      com,10,...
      'command output was:',10,...
      data_str])
  end
  if debug_now
    disp(['status = ',num2str(status)])
    disp('--- data_str start ---')
    disp(data_str)
    disp('--- data_str end ---')
  end

  %handle junk coming for the system command
  if ~isempty(strfind(data_str,27))
    %create a random anchor
    anchor=char(floor(25*rand(1,20)) + 65);
    %use system to echo the random anchor (along with the junk we want to remove)
    [~,echo_out]=system(['echo ',anchor]);
    %remove the random anchor from output of system, isolating the junk
    junk_str=strrep(echo_out,anchor,'');
    %remove the junk from data_str
    data_str=strrep(data_str,junk_str(1:end-1),'');
  end

  %number of data columns is the same as the number of products given in
  %input (NOTICE: this does not contemplate special fields, such as (e.g.):
  %SA_Basic/Accel_L1B/1-3
  a=textscan(product,'%s');
  if debug_now,disp('a='),disp(a{:}),end
  product_length=numel(a{1});
  if debug_now,disp(['product_length=',num2str(product_length)]),end

  %build the format specifiers, taking into account the number of products
  d='%f';
  fmt=[d,'-',d,'-',d,' ',d,':',d,':%6.3f %s',repmat(' %f',1,product_length)];
  if debug_now,disp(['fmt=',fmt]),end

  %parse data
  %2014-01-01 00:00:07.000 UTC -0.314819944E-04
  data_cell=textscan(data_str,fmt,...
    'Delimiter',' ',...
    'MultipleDelimsAsOne',true,...
    'CommentStyle','#'...
    );
  if debug_now,disp(['size(data_cell)=',num2str(size(data_cell))]),end

  %converting to matlab representation of time
  time=datetime(data_cell{1},data_cell{2},data_cell{3},data_cell{4},data_cell{5},data_cell{6});
  if debug_now,disp(['size(time)=',num2str(size(time))]),end

  %output
  values=cell2mat(data_cell(8:end));
  if debug_now,disp(['size(values)=',num2str(size(values))]),end

  if numel(values)==0
    keyboard
  end
end

% returns true if the modification date of file 1 is later than that of file 2.
function newer_file_flag=file_is_newer(file1,file2,disp_flag)

    if ~exist('disp_flag','var') || isempty(disp_flag)
        disp_flag=true;
    end

    f1=dir(file1);
    f2=dir(file2);

    if isempty(f1)
        if (disp_flag)
            disp([mfilename,':WARNING: cannot find file ',file1])
        end
        newer_file_flag=false;
        return
    end
    if isempty(f2)
        if (disp_flag)
            disp([mfilename,':WARNING: cannot find file ',file2])
        end
        newer_file_flag=true;
        return
    end
    if numel(f1)>1
        error([mfilename,':file_is_newer'],[' this is not a single file: ',file1])
    end
    if numel(f2)>1
        error([mfilename,':file_is_newer'],[': this is not a single file: ',file2])
    end

    newer_file_flag=datenum(f1.datenum)>datenum(f2.datenum);
end



